# frozen_string_literal: true

module Jekyll
module Plugins
module PaginateV3
module Pagination

# Core template-pagination pipeline helpers for `Model`.
# Structure: each template resolves items, filters/sorts them, emits
# pages, then wires trail and cross-page paginator references.
class Model

	private
	
	def paginate_template(template, config)
		template_path = Utils.relative_item_path(template)
		split_delimiter = config.key?('split') ? config['split'] : @split_delimiter
		nested_separator = config['separator'] || @nested_separator
		all_items = resolve_items(config['items'])
		@log_lambda.call("Template '#{template_path}': resolved #{all_items.length} candidate item(s).", 'debug')
		log_item_path_sample("Template '#{template_path}': candidate item sample", all_items)
		filtered_items = Query::Filter.filter_items(
			all_items,
			config['filters'],
			nested_separator: nested_separator,
			equivalents: @equivalents,
			split_delimiter: split_delimiter,
			now_keyword: config.dig('keywords', 'now') || @site_config.dig('keywords', 'now'),
			today_keyword: config.dig('keywords', 'today') || @site_config.dig('keywords', 'today'),
			log_lambda: @log_lambda,
			context_label: "Template '#{template_path}'"
		)
		@log_lambda.call("Template '#{template_path}': #{filtered_items.length} item(s) after filters=#{config['filters']}.", 'debug')
		log_item_path_sample("Template '#{template_path}': filtered item sample", filtered_items)

		sorted_items = Query::Sorter.apply(
			filtered_items,
			config['sort'],
			nested_separator: nested_separator,
			equivalents: @equivalents,
			split_delimiter: split_delimiter
		)
		@log_lambda.call("Template '#{template_path}': sorted #{sorted_items.length} item(s) by #{config['sort']} before offset.", 'debug')
		log_item_path_sample("Template '#{template_path}': sorted item sample", sorted_items)

		offset = [config['offset'].to_i, 0].max
		sorted_items = sorted_items.drop(offset)
		@log_lambda.call("Template '#{template_path}': #{sorted_items.length} item(s) after offset=#{offset}.", 'debug')
		log_item_path_sample("Template '#{template_path}': offset item sample", sorted_items)

		limit = [config['limit'].to_i, 0].max
		if limit.positive?
			original_item_count = sorted_items.length
			sorted_items = sorted_items.first(limit)
			@log_lambda.call("Template '#{template_path}': items limited from #{original_item_count} to #{sorted_items.length} by limit=#{limit}.", 'debug')
		end

		page_windows = Utils.build_pagination_windows(sorted_items.length, config['per_page'])
		total_pages = page_windows.length

		@log_lambda.call("Template '#{template_path}': generating #{total_pages} page(s) with per_page=#{config['per_page']} limit=#{config['limit']}.", 'debug')
		generated_pages = emit_paginated_pages(template, config, sorted_items, page_windows)
		register_grouped_set_if_applicable(template, config, generated_pages)
		{
			'paginated_items' => sorted_items.length,
			'indexes' => generated_pages.length
		}
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
			generated = build_generated_item(
				template: template,
				config: config,
				current_page: current_page,
				total_pages: total_pages,
				index_file: index_file
			)

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
			generated.data['pagination'].delete('enabled')
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

	# Builds one generated index object according to configured collection mode.
	def build_generated_item(template:, config:, current_page:, total_pages:, index_file:)
		target_mode = collection_target_mode_for_page(template, config, current_page)
		target_collection = collection_target_for_page(template, target_mode)

		case target_mode
		when 'pages'
			Pages::Page.new(template, current_page, total_pages, index_file)
		when 'shadow'
			Pages::ShadowPage.new(
				template,
				current_page,
				total_pages,
				index_file,
				collection: collection_template?(template) ? template.collection : nil
			)
		else
			if target_collection.nil?
				raise ArgumentError, "Unable to resolve collection target '#{target_mode}' for template '#{Utils.relative_item_path(template)}'."
			end

			Pages::Document.new(
				template,
				current_page,
				total_pages,
				index_file,
				collection: target_collection
			)
		end
	end

	# Resolves one normalised collection mode for a generated page number.
	def collection_target_mode_for_page(template, config, current_page)
		targets = Utils.arrayify(config['collection']).map(&:to_s).map(&:strip).reject(&:empty?)
		targets = ['self', 'shadow'] if targets.empty?
		target = current_page == 1 ? targets.first : targets.last

		normalise_collection_target_for_template(template, target)
	end

	# Resolves one collection object for collection-targeted modes.
	def collection_target_for_page(template, target_mode)
		case target_mode
		when 'self'
			return template.collection if collection_template?(template)
		when 'clone'
			return clone_collection_for(template.collection) if collection_template?(template)
		when 'pages', 'shadow'
			return nil
		end

		ensure_collection_exists(target_mode)
	end

	# Converts abstract target modes to executable runtime modes.
	def normalise_collection_target_for_template(template, target_mode)
		value = target_mode.to_s.strip
		value = 'pages' if value.empty?
		return value unless %w[self shadow clone].include?(value)
		return 'pages' unless collection_template?(template)
		return value if value == 'self'
		return value if value == 'clone'

		'shadow'
	end

	# Returns true when a template is a collection document.
	def collection_template?(template)
		template.is_a?(Jekyll::Document)
	end

	# Resolves or creates clone collection (`<source>_indexes`) for one source.
	def clone_collection_for(source_collection)
		source_label = source_collection.label.to_s
		return @clone_collection_cache[source_label] if @clone_collection_cache.key?(source_label)

		clone_label = "#{source_label}_indexes"
		collection = ensure_collection_exists(clone_label, clone_of: source_label)
		@clone_collection_cache[source_label] = collection
	end

	# Resolves a named collection, optionally creating and cloning config.
	def ensure_collection_exists(collection_label, clone_of: nil)
		label = collection_label.to_s.strip
		return nil if label.empty?

		collections = @site.collections
		return collections[label] if collections.key?(label)

			if clone_of.nil?
				raise ArgumentError, "Unknown collection '#{label}' configured in pagination.templates.collection or template pagination.collection."
			end

		ensure_collection_config!(label, clone_of)
		collection = Jekyll::Collection.new(@site, label)
		collections[label] = collection
		collection
	end

	# Copies collection and default config entries for clone collections.
	def ensure_collection_config!(clone_label, source_label)
		@site.config['collections'] ||= {}
		source_config = Utils.safe_hash(@site.config['collections'][source_label])
		@site.config['collections'][clone_label] = Utils.deep_copy(source_config)

		@site.config['defaults'] = Utils.arrayify(@site.config['defaults'])
		source_defaults = @site.config['defaults'].select do |entry|
			scope = Utils.safe_hash(Utils.safe_hash(entry)['scope'])
			scope['type'].to_s == source_label
		end

		source_defaults.each do |entry|
			clone_entry = Utils.deep_copy(entry)
			clone_entry['scope'] ||= {}
			clone_entry['scope']['type'] = clone_label
			@site.config['defaults'] << clone_entry
		end

		@site.frontmatter_defaults.reset if @site.respond_to?(:frontmatter_defaults)
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
