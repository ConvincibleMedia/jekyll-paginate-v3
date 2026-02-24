# frozen_string_literal: true

module Jekyll
module Plugins
module PaginateV3
module Pagination
class Model
	# Core template-pagination pipeline helpers for `Model`.
	# Structure: each template resolves items, filters/sorts them, emits
	# pages, then wires trail and cross-page paginator references.

	private
	def paginate_template(template, config)
		split_delimiter = config['split'] || @split_delimiter
		nested_separator = config['separator'] || @nested_separator
		all_items = resolve_items(config['items'])
		@log_lambda.call("Template '#{Utils.relative_item_path(template)}': resolved #{all_items.length} candidate item(s).", 'debug')
		filtered_items = Query::Filter.filter_items(
			all_items,
			config['filters'],
			nested_separator: nested_separator,
			equivalents: @equivalents,
			split_delimiter: split_delimiter,
			now_keyword: config.dig('keywords', 'now') || @site_config.dig('keywords', 'now'),
			today_keyword: config.dig('keywords', 'today') || @site_config.dig('keywords', 'today'),
			log_lambda: @log_lambda
		)
		@log_lambda.call("Template '#{Utils.relative_item_path(template)}': #{filtered_items.length} item(s) after filters=#{config['filters']}.", 'debug')

		sorted_items = Query::Sorter.apply(
			filtered_items,
			config['sort'],
			nested_separator: nested_separator,
			equivalents: @equivalents,
			split_delimiter: split_delimiter
		)
		@log_lambda.call("Template '#{Utils.relative_item_path(template)}': sorted #{sorted_items.length} item(s) by #{config['sort']} before offset.", 'debug')

		offset = [config['offset'].to_i, 0].max
		sorted_items = sorted_items.drop(offset)
		@log_lambda.call("Template '#{Utils.relative_item_path(template)}': #{sorted_items.length} item(s) after offset=#{offset}.", 'debug')

		page_windows = Utils.build_pagination_windows(sorted_items.length, config['per_page'])
		# `limit` caps the number of emitted index pages, not the source items.
		if config['limit'].to_i > 0
			page_windows = page_windows.first(config['limit'].to_i)
		end
		total_pages = page_windows.length

		@log_lambda.call("Template '#{Utils.relative_item_path(template)}': generating #{total_pages} page(s) with per_page=#{config['per_page']} limit=#{config['limit']}.", 'debug')
		generated_pages = emit_paginated_pages(template, config, sorted_items, page_windows)
		register_grouped_set_if_applicable(template, config, generated_pages)
	end

	# Replaces a template with one synthetic page/document per page number.
	def emit_paginated_pages(template, config, items, page_windows)
		@remove_item_lambda.call(template)

		new_pages = []
		total_pages = page_windows.length

		# Generated pages/documents should be processed as ordinary Jekyll
		# items, so we only set frontmatter and never force synthetic URLs.
		index_file = 'index.html'

		page_windows.each do |page_window|
			current_page = page_window['num']
			# Preserve the source item type: collection templates emit documents,
			# page templates emit pages.
			generated = if template.respond_to?(:collection)
										Pages::Document.new(template, current_page, total_pages, index_file)
									else
										Pages::Page.new(template, current_page, total_pages, index_file)
									end

			generated.pager = Paginator.new(
				per_page: config['per_page'],
				items: items,
				current_page: current_page,
				total_pages: total_pages,
				item_keyword: @item_keyword,
				compatibility: config['compatibility'],
				page_windows: page_windows
			)

			generated.data['pagination'] = Utils.safe_hash(generated.data['pagination'])
			generated.data['pagination'].delete('template')
			generated.data['pagination']['index'] = true

			# Only mark emitted indexes as generated when their source
			# template came from the template-generation pipeline.
			if template.data.dig('paginate_v3', 'generated_template')
				generated.data['pagination']['generated'] = true
			else
				generated.data['pagination'].delete('generated')
			end
			generated.data['paginator'] = generated.pager
			generated.data.delete('paginate_v3')
			generated.data['autogen'] = 'jekyll-paginate-v2' if config['compatibility'] == 'v2'

			assign_generated_page_title!(generated, template, config, current_page, total_pages)
			assign_generated_page_permalink!(generated, template, config, current_page, total_pages)

			@add_item_lambda.call(generated)
			@log_lambda.call("Emitted pagination page #{current_page}/#{total_pages} at '#{generated.url}' for template '#{Utils.relative_item_path(template)}'.", 'debug')
			new_pages << generated
		end

		bind_paginator_references(new_pages)
		apply_page_trail(new_pages, config)
		new_pages
	end

	# Attaches a compact neighbourhood of page links around each generated
	# page when `trail.before/after` is configured.
	def apply_page_trail(generated_pages, config)
		return if generated_pages.length <= 1
		return unless config['trail'].is_a?(Hash)

		before = [config['trail']['before'].to_i, 0].max
		after = [config['trail']['after'].to_i, 0].max
		return if before.zero? && after.zero?

		trail_size = before + after + 1
		@log_lambda.call("Applying page trail with before=#{before} after=#{after} size=#{trail_size} across #{generated_pages.length} generated page(s).", 'debug')

		generated_pages.each do |page|
			current_page_number = page.pager.current.num
			range_start = [current_page_number - before - 1, 0].max
			range_end = [range_start + trail_size, generated_pages.length].min

			# When near the end, shift left so the trail remains the configured size.
			if range_end - range_start < trail_size
				range_start = [range_start - (trail_size - (range_end - range_start)), 0].max
			end

			page.pager.trail = generated_pages[range_start...range_end].each_with_index.map do |trail_page, index|
				trail_number = range_start + index + 1
				is_current_page = trail_number == current_page_number

				page.pager.build_trail_reference(
					page_number: trail_number,
					page_object: is_current_page ? nil : trail_page,
					current: is_current_page,
					distance: trail_number - current_page_number
				)
			end
			@log_lambda.call("Assigned trail to page #{current_page_number}: range_start=#{range_start + 1} range_end=#{range_end}.", 'debug')
		end
	end

	# Populates paginator neighbour references once all pages are created.
	def bind_paginator_references(generated_pages)
		return if generated_pages.empty?

		generated_pages.each_with_index do |page, index|
			page.pager.bind_pages(
				current_page_object: page,
				previous_page_object: index.positive? ? generated_pages[index - 1] : nil,
				next_page_object: index < generated_pages.length - 1 ? generated_pages[index + 1] : nil,
				first_page_object: generated_pages.first,
				last_page_object: generated_pages.last
			)
		end
	end

	# Registers generated index sets so cross-set navigation can be
	# attached after all templates are emitted.
	def register_grouped_set_if_applicable(template, config, generated_pages)
		return if generated_pages.nil? || generated_pages.empty?

		group_metadata_entries = Utils.arrayify(template.data.dig('paginate_v3', 'groups')).map { |entry| Utils.safe_hash(entry) }.reject(&:empty?)
		return if group_metadata_entries.empty?

		group_metadata_entries.each do |metadata|
			set_id = metadata['set_id'].to_s
			# Ignore incomplete metadata entries; grouped navigation requires a set id.
			next if set_id.empty?

			@generated_index_sets[set_id] ||= []
			@generated_index_sets[set_id] << {
				'pages' => generated_pages,
				'count' => generated_pages.first.pager.total_items,
				'start' => metadata['start'],
				'end' => metadata['end'],
				'order' => metadata['order'].to_i,
				'other' => !!metadata['other'],
				'depth' => metadata['depth'].to_i,
				'index_key' => metadata['key'].to_s,
				'sort_direction' => grouped_set_sort_direction(config, metadata['key'].to_s)
			}
		end
	end

end
end
end
end
end
