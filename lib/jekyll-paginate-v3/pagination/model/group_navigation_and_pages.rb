# frozen_string_literal: true

module Jekyll
module Plugins
module PaginateV3
module Pagination

# Group navigation and generated-page metadata helpers for `Model`.
# Structure: grouped index sets are ordered, converted into paginator
# payloads, and then applied to every generated pagination page.
class Model

	private

	def apply_grouped_set_navigation!
		if @generated_index_sets.empty?
			@log_lambda.call('Grouped navigation: no grouped index sets were registered.', 'debug')
			return
		end

		page_group_payloads = {}
		page_objects = {}

		@generated_index_sets.each do |set_id, set_entries|
			next if set_entries.empty?

			ordered_entries = ordered_grouped_set_entries(set_entries)
			next if ordered_entries.empty?
			@log_lambda.call("Grouped navigation: set='#{set_id}' entries=#{ordered_entries.length}.", 'debug')

			ordered_entries.each_with_index do |entry, index|
				current_number = index + 1
				previous_entry = index.positive? ? ordered_entries[index - 1] : nil
				next_entry = index < ordered_entries.length - 1 ? ordered_entries[index + 1] : nil
				first_entry = ordered_entries.first
				last_entry = ordered_entries.last

				group_payload = Paginator::GroupPayload.new(
					key: entry['index_key'],
					current: build_group_reference(entry, current_number, include_page: false),
					next_reference: next_entry.nil? ? nil : build_group_reference(next_entry, current_number + 1, include_page: true),
					first_reference: build_group_reference(first_entry, 1, include_page: true),
					last_reference: build_group_reference(last_entry, ordered_entries.length, include_page: true),
					previous_reference: previous_entry.nil? ? nil : build_group_reference(previous_entry, current_number - 1, include_page: true)
				)

				entry['pages'].each do |page|
					# Pages can appear in multiple grouped levels; keep payloads by depth.
					page_identifier = page.object_id
					page_objects[page_identifier] = page
					page_group_payloads[page_identifier] ||= {}
					page_group_payloads[page_identifier][entry['depth']] = group_payload
				end
			end
		end

		page_group_payloads.each do |page_identifier, payloads_by_depth|
			page = page_objects[page_identifier]
			next if page.nil?

			ordered_payloads = payloads_by_depth.sort_by { |depth, _| depth }.map { |_, payload| payload }
			page.pager.groups = ordered_payloads
		end

		@log_lambda.call("Grouped navigation: assigned payloads to #{page_group_payloads.length} page(s).", 'debug')
	end

	# Orders grouped-set entries according to configured sort direction.
	#
	# When index key sort is not explicit, grouped sets default to
	# ascending order. Alphabetic `other` groups are always placed last.
	def ordered_grouped_set_entries(set_entries)
		return set_entries if set_entries.length <= 1

		direction = set_entries.first['sort_direction']
		main_entries = set_entries.reject { |entry| entry['other'] }
		other_entries = set_entries.select { |entry| entry['other'] }

		sorted_main = main_entries.sort_by { |entry| entry['order'] }
		sorted_main.reverse! if direction == 'desc'

		# `other` groups are always shown last regardless of sort direction.
		sorted_main + other_entries
	end

	# Detects grouped-set direction from template sort config.
	def grouped_set_sort_direction(config, index_key)
		return 'asc' if index_key.to_s.strip.empty?

		split_delimiter = config['split'] || @split_delimiter
		sort_instructions = Query::Sorter.parse(config['sort'], split_delimiter: split_delimiter)
		sort_entry = sort_instructions.find { |entry| entry['field'] == index_key }
		return 'asc' if sort_entry.nil?

		sort_entry['direction']
	end

	# Builds one grouped-set reference object used by `paginator.group`.
	def build_group_reference(entry, number, include_page:)
		Paginator::GroupReference.new(
			num: number,
			page_object: include_page ? entry['pages'].first : nil,
			item_count: entry['count'],
			range_start: entry['start'],
			range_end: entry['end']
		)
	end

	# Applies configured page title templates.
	def assign_generated_page_title!(generated, template, config, current_page, total_pages)
		page_template = page_template_config(config, current_page)
		base_title = template.data['title'] || @site.config['title']
		generated.data['title'] = Utils.format_page_title(page_template['title'], base_title, current_page, total_pages)
	end

	# Applies configured page permalink templates.
	def assign_generated_page_permalink!(generated, template, config, current_page, total_pages)
		resolved_permalink = resolved_page_permalink(template, config, current_page, total_pages)

		if resolved_permalink.nil?
			generated.data.delete('permalink') if current_page > 1
			return
		end

		generated.data['permalink'] = resolved_permalink
	end

	# Resolves one page permalink from page1/page2 template settings.
	def resolved_page_permalink(template, config, current_page, total_pages)
		page_template = page_template_config(config, current_page)
		template_permalink = Utils.format_page_number(page_template['permalink'], current_page, total_pages)
		return Utils.ensure_leading_slash(template_permalink) if v1_absolute_paginate_path?(config, current_page)

		first_page_url = template_first_page_url(template)
		return first_page_url if template_permalink.to_s.strip.empty?

		join_url(first_page_url, template_permalink)
	end

	# Determines whether this page should use v1-style absolute paginate_path.
	def v1_absolute_paginate_path?(config, current_page)
		return false if current_page == 1
		return false unless config['compatibility'] == 'v1'
		return false unless legacy_v1_site_config_present?
		return false if @site.config['paginate_path'].nil?

		true
	end

	# Returns page template settings for page1 or page2+.
	def page_template_config(config, current_page)
		page_templates = Utils.safe_hash(config['page_templates'])
		key = current_page == 1 ? 'page1' : 'page2'
		template = Utils.safe_hash(page_templates[key])
		return template unless template.empty?

		if current_page == 1
			{
				'title' => ':title',
				'permalink' => ''
			}
		else
			{
				'title' => config['title'].to_s,
				'permalink' => config['permalink'].to_s
			}
		end
	end

	# Determines the canonical URL for the first pagination page of a template.
	def template_first_page_url(template)
		permalink = template.data['permalink']
		unless permalink.nil? || permalink.to_s.strip.empty?
			return Utils.ensure_leading_slash(permalink.to_s)
		end

		if template.respond_to?(:url) && !template.url.to_s.strip.empty?
			return Utils.ensure_leading_slash(template.url.to_s)
		end

		if template.respond_to?(:cleaned_relative_path)
			return "/#{template.cleaned_relative_path}/"
		end

		"/#{Utils.remove_leading_slash(File.join(template.dir.to_s, template.basename.to_s))}/"
	end

	# Joins a base URL and relative suffix while preserving one leading slash.
	def join_url(base_url, suffix)
		joined = "#{Utils.ensure_trailing_slash(base_url)}#{Utils.remove_leading_slash(suffix.to_s)}"
		Utils.ensure_leading_slash(joined)
	end
end

end
end
end
end
