# frozen_string_literal: true

require 'digest'

module Jekyll
module Plugins
module PaginateV3
module Templates

# Expands template pagination config into concrete variants before the
# paginator emits index pages.
#
# This class generalises grouped and multi-layout behaviour so both
# explicit templates and generated templates share one execution path.
class VariantExpander

	# Builds an expander for one template and its normalised pagination config.
	def initialize(site:, site_config:, template:, template_config:, template_pagination_source:, merge_template_pagination_lambda:, normalise_template_config_lambda:, resolve_items_lambda:, log_lambda:)
		@site = site
		@site_config = site_config
		@template = template
		@template_config = template_config
		@template_pagination_source = Utils.safe_hash(template_pagination_source)
		@merge_template_pagination_lambda = merge_template_pagination_lambda
		@normalise_template_config_lambda = normalise_template_config_lambda
		@resolve_items_lambda = resolve_items_lambda
		@log_lambda = log_lambda
		@equivalents = site_config['equivalents']
		@active_template_config = Utils.deep_copy(template_config)
		@active_split_delimiter = @active_template_config.key?('split') ? @active_template_config['split'] : site_config.dig('syntax', 'split')
		@active_nested_separator = @active_template_config['separator'] || site_config.dig('syntax', 'separator')
		@site_frontmatter_path = Jekyll::Plugins::PaginateV3::Support::FrontmatterPath.new(
			separator: site_config.dig('syntax', 'separator'),
			arrays: :expand,
			equivalents: @equivalents
		)
		@site_string_array = Jekyll::Plugins::PaginateV3::Support::StringArray.new(delimiter: site_config.dig('syntax', 'split'))
		@active_frontmatter_path = @site_frontmatter_path.with(separator: @active_nested_separator)
		@active_string_array = @site_string_array.with(delimiter: @active_split_delimiter)
	end

	# Expands one template into grouped/layout variants.
	def expand
		layout_entries = Utils.arrayify(@template_config['layouts']).map { |entry| entry.to_s.strip }.reject(&:empty?)
		layout_entries = [nil] if layout_entries.empty?

		build_variants(layout_entries)
	end

	private

	# Executes one block with active config values scoped to the provided
	# template config.
	def with_template_config(template_config)
		previous_template_config = @active_template_config
		previous_split_delimiter = @active_split_delimiter
		previous_nested_separator = @active_nested_separator

		@active_template_config = Utils.deep_copy(template_config)
		@active_split_delimiter = @active_template_config.key?('split') ? @active_template_config['split'] : @site_config.dig('syntax', 'split')
		@active_nested_separator = @active_template_config['separator'] || @site_config.dig('syntax', 'separator')
		@active_frontmatter_path = @site_frontmatter_path.with(separator: @active_nested_separator)
		@active_string_array = @site_string_array.with(delimiter: @active_split_delimiter)

		yield
	ensure
		@active_template_config = previous_template_config
		@active_split_delimiter = previous_split_delimiter
		@active_nested_separator = previous_nested_separator
		@active_frontmatter_path = @site_frontmatter_path.with(separator: @active_nested_separator)
		@active_string_array = @site_string_array.with(delimiter: @active_split_delimiter)
	end

	# Returns base items for grouped expansion after template-level filters.
	def filtered_items_for_grouping
		items = @resolve_items_lambda.call(@active_template_config['items'])
		filters = Utils.safe_hash(@active_template_config['filters'])
		return items if filters.empty?

		Query::Filter.filter_items(
			items,
			filters,
			nested_separator: @active_nested_separator,
			equivalents: @equivalents,
			split_delimiter: @active_split_delimiter,
			now_keyword: @active_template_config.dig('keywords', 'now') || @site_config.dig('keywords', 'now'),
			today_keyword: @active_template_config.dig('keywords', 'today') || @site_config.dig('keywords', 'today'),
			log_lambda: @log_lambda,
			context_label: "Template '#{Utils.relative_item_path(@template)}' (group setup)"
		)
	end

	# Builds grouped combinations from configured `pagination.group` entries.
	def build_group_entries(items, group_entries)
		if group_entries.empty?
			return [
				{
					'filters' => {},
					'values' => {},
					'token_values' => {},
					'levels' => []
				}
			]
		end

		entries = []
		recurse_build_entries(items, group_entries, 0, {}, {}, {}, [], entries)
		entries
	end

	# Depth-first grouping for `pagination.group` entries.
	def recurse_build_entries(items, group_entries, depth, active_filters, active_values, active_token_values, active_levels, entries)
		if depth >= group_entries.length
			entries << {
				'filters' => Utils.deep_copy(active_filters),
				'values' => Utils.deep_copy(active_values),
				'token_values' => Utils.deep_copy(active_token_values),
				'levels' => Utils.deep_copy(active_levels)
			}
			return
		end

		entry_spec = group_entries[depth]
		key = entry_spec['on'].to_s.strip
		return if key.empty?

		groups_for_entry(items, key, entry_spec).each_with_index do |group, group_index|
			next if group['token'].nil? || group['token'].empty?

			next_filters = active_filters.merge(key => group['filter_value'])
			next_values = active_values.merge(key => group['display_name'])
			next_token_values = Utils.deep_copy(active_token_values)
			if group['token_values'].is_a?(Hash) && !group['token_values'].empty?
				next_token_values[key] = Utils.deep_copy(group['token_values'])
			end

			level_info = {
				'key' => key,
				'order' => group['order'].to_i.positive? ? group['order'].to_i : (group_index + 1),
				'start' => group.key?('start') ? group['start'] : group['display_name'],
				'end' => group['end'],
				'other' => !!group['other'],
				'range' => !!group['range']
			}
			next_levels = active_levels + [level_info]

			recurse_build_entries(
				group['items'],
				group_entries,
				depth + 1,
				next_filters,
				next_values,
				next_token_values,
				next_levels,
				entries
			)
		end
	end

	# Resolves grouping for one entry from grouped ranges or unique values.
	def groups_for_entry(items, key, entry_spec)
		scoped_items = apply_group_filter(items, key, entry_spec['filter'])
		return [] if scoped_items.empty?

		if entry_spec.key?('size') && present_config_value?(entry_spec['size'])
			grouped_entries_for_size(key, entry_spec['size'], scoped_items)
		else
			group_items_by_key(scoped_items, key).each_with_index.map do |group, index|
				group.merge(
					'token_values' => {},
					'start' => group['display_name'],
					'end' => nil,
					'other' => false,
					'range' => false,
					'order' => index + 1
				)
			end
		end
	end

	# Applies one per-group filter, scoped to the grouped key.
	def apply_group_filter(items, key, raw_filter)
		return items unless present_config_value?(raw_filter)

		Query::Filter.filter_items(
			items,
			{ key => raw_filter },
			nested_separator: @active_nested_separator,
			equivalents: @equivalents,
			split_delimiter: @active_split_delimiter,
			now_keyword: @active_template_config.dig('keywords', 'now') || @site_config.dig('keywords', 'now'),
			today_keyword: @active_template_config.dig('keywords', 'today') || @site_config.dig('keywords', 'today'),
			log_lambda: @log_lambda,
			context_label: "Template '#{Utils.relative_item_path(@template)}' (group key='#{key}')"
		)
	end

	# Expands grouped-range entries for one key.
	def grouped_entries_for_size(key, raw_size, items)
		grouped_entries = GroupedIndex.new(
			key: key,
			raw_group: raw_size,
			items: items,
			nested_separator: @active_nested_separator,
			split_delimiter: @active_split_delimiter,
			equivalents: @equivalents,
			now_keyword: @site_config.dig('keywords', 'now'),
			today_keyword: @site_config.dig('keywords', 'today'),
			keywords: @site_config['keywords'],
			log_lambda: @log_lambda
		).build_entries

		grouped_entries.map do |entry|
			group_metadata = Utils.safe_hash(entry['group'])
			{
				'token' => entry.dig('values', key).to_s,
				'display_name' => entry.dig('values', key),
				'filter_value' => entry.dig('filters', key),
				'items' => Utils.arrayify(entry['items']).uniq,
				'token_values' => Utils.safe_hash(entry.dig('token_values', key)),
				'start' => group_metadata.key?('start') ? group_metadata['start'] : entry.dig('values', key),
				'end' => group_metadata['end'],
				'other' => !!group_metadata['other'],
				'range' => !!group_metadata['range'],
				'order' => group_metadata['order']
			}
		end
	end

	# Groups items by one frontmatter key using slugified tokens.
	def group_items_by_key(items, key)
		grouped = {}
		slugify_config = Utils.safe_hash(@active_template_config['slugify'])

		items.each do |item|
			values = values_for_key(item, key)
			values.each do |value|
				token = slugify_value(value, slugify_config: slugify_config)
				next if token.empty?

				group = grouped[token]
				if group.nil?
					group = {
						'token' => token,
						'display_name' => value,
						'raw_values' => [],
						'items' => []
					}
					grouped[token] = group
				end

				group['raw_values'] << value unless group['raw_values'].include?(value)
				group['items'] << item
			end
		end

		grouped.values.map do |group|
			{
				'token' => group['token'],
				'display_name' => group['display_name'],
				'filter_value' => group['raw_values'].length == 1 ? group['raw_values'].first : group['raw_values'],
				'items' => group['items'].uniq
			}
		end.sort_by { |group| group['token'] }
	end

	# Extracts scalar values for one key, including nested/equivalent keys.
	def values_for_key(item, key)
		data = item.respond_to?(:data) && item.data.is_a?(Hash) ? item.data.dup : {}
		collection_label = Utils.item_collection_label(item)
		data['collection'] = collection_label unless collection_label.nil?

		values = Utils.scalar_values(@active_frontmatter_path.traverse(data, key)).flat_map do |value|
			if value.is_a?(String)
				@active_string_array.interpret(value, split: 0, flatten: true)
			else
				[value]
			end
		end

		values.map { |value| value.to_s.strip }.reject(&:empty?).uniq
	end

	# Builds concrete template/config variants for grouped and layout entries.
	def build_variants(layout_entries)
		variants = []
		base_template_snapshot = clone_template(@template)

		layout_entries.each do |layout_name|
			layout_state = layout_variant_state(base_template_snapshot, layout_name)
			with_template_config(layout_state['config']) do
				group_entries = Utils.arrayify(layout_state['config']['group']).map { |entry| Utils.safe_hash(entry) }.reject(&:empty?)
				grouped_entries = build_group_entries(filtered_items_for_grouping, group_entries)
				next if grouped_entries.empty?

				grouped_entries.each do |entry|
					variant_template = variants.empty? ? @template : clone_template(@template)
					reset_template_from_snapshot!(variant_template, base_template_snapshot)
					apply_layout_override!(variant_template, layout_name)

					variant_config = Utils.deep_copy(layout_state['config'])
					token_maps = build_token_maps(
						entry,
						slugify_config: Utils.safe_hash(variant_config['slugify']),
						compatibility_mode: variant_config['compatibility']
					)

					grouped_permalink = grouped_permalink_state(variant_template, variant_config, entry)
					grouped_template_permalink = if grouped_permalink.nil?
														nil
													else
														Utils.replace_tokens(grouped_permalink['template_permalink'], token_maps['permalink'])
													end
					apply_token_overrides_to_template!(
						variant_template,
						token_maps,
						grouped_template_permalink: grouped_template_permalink
					)
					apply_group_metadata_to_template!(
						variant_template,
						entry,
						layout_name,
						token_maps,
						compatibility_mode: variant_config['compatibility']
					)

					variant_config['filters'] = Utils.deep_copy(variant_config['filters']).merge(entry['filters'])
					variant_config['title'] = Utils.replace_tokens(variant_config['title'], token_maps['title'])
					if grouped_permalink.nil?
						variant_config['permalink'] = Utils.replace_tokens(variant_config['permalink'], token_maps['permalink'])
					else
						variant_config['permalink'] = grouped_permalink['page2_permalink'].to_s
						variant_config['page_templates'] = apply_grouped_page2_permalink_template(
							variant_config['page_templates'],
							variant_config['permalink']
						)
					end
					variant_config['page_templates'] = tokenised_page_templates(
						variant_config['page_templates'],
						token_maps,
						fallback_title: variant_config['title'],
						fallback_permalink: variant_config['permalink'],
						replace_page2_permalink_tokens: grouped_permalink.nil?
					)
					variant_config['group'] = []
					variant_config['layouts'] = []

					apply_variant_pagination_payload!(variant_template, variant_config)

					variants << {
						'template' => variant_template,
						'config' => variant_config
					}
				end
			end
		end

		variants
	end

	# Resolves grouped permalink part1/part2 behaviour from docs:
	# - two configured parts map to grouped template permalink + page2 permalink
	# - one configured part is treated as page2 permalink only
	# - missing grouped placeholders are implicitly prepended to part1
	def grouped_permalink_state(template, variant_config, entry)
		group_keys = grouped_permalink_keys(entry)
		return nil if group_keys.empty?

		first_part, second_part = split_grouped_permalink_definition(variant_config['permalink'])
		unless present_config_value?(first_part)
			first_part = Utils.safe_hash(template.data)['permalink']
		end
		first_part = prepend_missing_group_placeholders(
			first_part,
			group_keys,
			compatibility_mode: variant_config['compatibility']
		)
		first_part = resolve_grouped_template_permalink(template, first_part)

		{
			'template_permalink' => first_part.to_s,
			'page2_permalink' => second_part.to_s
		}
	end

	# Resolves grouped template permalink part1 relative to template route.
	#
	# Absolute part1 values (starting with `/`) remain absolute. Relative
	# part1 values are resolved against the source template permalink/URL.
	def resolve_grouped_template_permalink(template, raw_part1)
		part1 = raw_part1.to_s.strip
		return part1 if part1.start_with?('/')

		join_permalink_segments(base_template_permalink(template), part1)
	end

	# Returns the base permalink/URL for resolving grouped relative paths.
	def base_template_permalink(template)
		data = Utils.safe_hash(template.data)
		permalink = data['permalink'].to_s.strip
		if permalink.empty? && template.respond_to?(:url)
			permalink = template.url.to_s.strip
		end
		permalink = '/' if permalink.empty?

		Utils.ensure_leading_slash(permalink)
	end

	# Returns grouped keys in declaration order for one grouped entry.
	def grouped_permalink_keys(entry)
		Utils.arrayify(entry['levels']).map do |level|
			Utils.safe_hash(level)['key'].to_s.strip
		end.reject(&:empty?)
	end

	# Splits grouped permalink definition into `[part1, part2]`.
	#
	# Two parts: `part1 part2`
	# One part: treated as `part2` only (`part1` is nil)
	def split_grouped_permalink_definition(raw_permalink)
		parts = raw_permalink.to_s.strip.split(/\s+/, 2).map { |part| part.to_s.strip }
		if parts.length >= 2
			[parts[0], parts[1]]
		elsif parts.length == 1 && !parts[0].empty?
			[nil, parts[0]]
		else
			[nil, '']
		end
	end

	# Prepends grouped placeholders that are missing from permalink part1.
	def prepend_missing_group_placeholders(first_part, group_keys, compatibility_mode:)
		part1 = first_part.to_s.strip
		present_keys = matched_placeholder_keys(part1, group_keys, compatibility_mode: compatibility_mode)
		missing_placeholders = group_keys.reject { |key| present_keys.include?(key) }.map { |key| ":#{key}" }
		return part1 if missing_placeholders.empty?

		join_permalink_segments(missing_placeholders.join('/'), part1)
	end

	# Detects grouped placeholders already present in a permalink part.
	def matched_placeholder_keys(permalink_part, group_keys, compatibility_mode:)
		keys = group_keys.map(&:to_s).reject(&:empty?).uniq
		return [] if keys.empty?

		token_to_key = keys.each_with_object({}) { |key, map| map[key] = key }
		if compatibility_mode == 'v2'
			token_to_key['cat'] = 'category' if keys.include?('category')
			token_to_key['coll'] = 'collection' if keys.include?('collection')
		end

		sorted_tokens = token_to_key.keys.sort_by { |token| [-token.length, token] }
		placeholder_pattern = /:(#{sorted_tokens.map { |token| Regexp.escape(token) }.join('|')})/
		permalink_part.to_s.scan(placeholder_pattern).flatten.map { |token| token_to_key[token] }.uniq
	end

	# Joins two permalink fragments with exactly one slash separator.
	def join_permalink_segments(prefix, suffix)
		prefix_part = prefix.to_s.strip
		suffix_part = suffix.to_s.strip
		return suffix_part if prefix_part.empty?
		return prefix_part if suffix_part.empty?

		"#{prefix_part.sub(%r{/\z}, '')}/#{suffix_part.sub(%r{\A/}, '')}"
	end

	# Rewrites page2 permalink template for grouped permalink part2 handling.
	def apply_grouped_page2_permalink_template(raw_page_templates, page2_permalink)
		page_templates = Utils.safe_hash(raw_page_templates)
		page2_template = Utils.safe_hash(page_templates['page2'])
		page2_template['permalink'] = page2_permalink.to_s
		page_templates['page2'] = page2_template
		page_templates
	end

	# Resolves one layout-specific merged/normalised config pair.
	def layout_variant_state(base_template_snapshot, layout_name)
		layout_template = clone_template(@template)
		reset_template_from_snapshot!(layout_template, base_template_snapshot)
		apply_layout_override!(layout_template, layout_name)

		merged_pagination = @merge_template_pagination_lambda.call(layout_template, @template_pagination_source)
		{
			'merged_pagination' => merged_pagination,
			'config' => @normalise_template_config_lambda.call(merged_pagination)
		}
	end

	# Stores the effective variant pagination payload on the template so
	# emitted indexes can expose the resolved config under `page.pagination`.
	def apply_variant_pagination_payload!(template, variant_config)
		data = Utils.safe_hash(template.data)
		data['pagination'] = Utils.deep_copy(variant_config)
		replace_template_data!(template, data)
	end

	# Clones template data/content so per-variant mutations remain isolated.
	def clone_template(template)
		cloned_template = template.dup
		replace_template_data!(cloned_template, template.data)
		cloned_template.content = template.content.to_s if cloned_template.respond_to?(:content=)
		cloned_template
	end

	# Resets mutable template fields from an immutable snapshot.
	def reset_template_from_snapshot!(template, snapshot)
		replace_template_data!(template, snapshot.data)
		template.content = snapshot.content.to_s if template.respond_to?(:content=)
	end

	# Applies placeholder replacement on template frontmatter values.
	def apply_token_overrides_to_template!(template, token_maps, grouped_template_permalink: nil)
		data = Utils.safe_hash(template.data)

		if data['title'].is_a?(String)
			data['title'] = Utils.replace_tokens(data['title'], token_maps['title'])
		end
		if grouped_template_permalink.is_a?(String)
			data['permalink'] = grouped_template_permalink
		elsif data['permalink'].is_a?(String)
			data['permalink'] = Utils.replace_tokens(data['permalink'], token_maps['permalink'])
		end
		if template.respond_to?(:content=)
			template.content = Utils.replace_tokens(template.content.to_s, token_maps['title'])
		end

		replace_template_data!(template, data)
	end

	# Applies one per-variant layout override when configured.
	def apply_layout_override!(template, layout_name)
		return if layout_name.nil? || layout_name.to_s.strip.empty?

		layout_value = Utils.normalise_layout_name(layout_name)
		data = Utils.safe_hash(template.data)
		data['layout'] = layout_value
		replace_template_data!(template, data)
	end

	# Attaches grouped-set metadata used to build `paginator.groups`.
	def apply_group_metadata_to_template!(template, entry, layout_name, token_maps, compatibility_mode:)
		group_levels = build_group_level_metadata(entry, layout_name)

		paginate_metadata = Utils.safe_hash(template.data['paginate_v3'])
		if group_levels.empty?
			paginate_metadata.delete('groups')
		else
			paginate_metadata['groups'] = group_levels
		end
		apply_v2_autopages_metadata!(template, entry, token_maps, paginate_metadata, compatibility_mode: compatibility_mode)

		if paginate_metadata.empty?
			template.data.delete('paginate_v3')
		else
			template.data['paginate_v3'] = paginate_metadata
		end
	end

	# Applies v2 autopages metadata for single-level grouped templates.
	def apply_v2_autopages_metadata!(template, entry, token_maps, paginate_metadata, compatibility_mode:)
		return unless compatibility_mode == 'v2'

		levels = Utils.arrayify(entry['levels'])
		if levels.length != 1
			paginate_metadata.delete('autopages')
			template.data.delete('autopages')
			return
		end

		key = levels.first['key'].to_s
		display_name = entry.dig('values', key).to_s
		token_value = token_maps.dig('compatibility', key).to_s
		autopages_payload = {
			'key' => key,
			'value' => token_value,
			'display_name' => display_name
		}

		paginate_metadata['autopages'] = autopages_payload
		template.data['autopages'] = autopages_payload
		if key != 'collection' && !key.include?('.') && !key.include?(':')
			template.data[key] = token_value
		end
	end

	# Builds title/permalink token maps for grouped placeholders.
	def build_token_maps(entry, slugify_config:, compatibility_mode:)
		levels = Utils.arrayify(entry['levels'])
		values = Utils.safe_hash(entry['values'])
		token_values = Utils.safe_hash(entry['token_values'])

		title_tokens = {}
		permalink_tokens = {}
		compatibility_tokens = {}

		levels.each do |level|
			key = level['key'].to_s
			next if key.empty?

			value = values[key]
			configured_token_values = Utils.safe_hash(token_values[key])
			slugified_value = slugify_value(value, slugify_config: slugify_config)

			title_tokens[key] = if configured_token_values.key?('title')
									configured_token_values['title'].to_s
								else
									slugified_value
								end
			permalink_tokens[key] = if configured_token_values.key?('permalink')
										configured_token_values['permalink'].to_s
									else
										slugified_value
									end
			compatibility_tokens[key] = slugified_value
		end

		apply_legacy_token_aliases!(title_tokens, compatibility_mode: compatibility_mode)
		apply_legacy_token_aliases!(permalink_tokens, compatibility_mode: compatibility_mode)
		apply_legacy_token_aliases!(compatibility_tokens, compatibility_mode: compatibility_mode)

		{
			'title' => title_tokens,
			'permalink' => permalink_tokens,
			'compatibility' => compatibility_tokens
		}
	end

	# Applies v2 legacy token aliases (`:coll`, `:cat`, `:tag`).
	def apply_legacy_token_aliases!(token_map, compatibility_mode:)
		return unless compatibility_mode == 'v2'

		if token_map.key?('collection')
			token_map['coll'] = token_map['collection']
		end
		if token_map.key?('category') || token_map.key?('categories')
			token_map['cat'] = token_map['category'] || token_map['categories']
		end
		if token_map.key?('tag') || token_map.key?('tags')
			token_map['tag'] = token_map['tag'] || token_map['tags']
		end
	end

	# Builds grouped navigation metadata payloads for each group depth.
	def build_group_level_metadata(entry, layout_name)
		levels = Utils.arrayify(entry['levels'])
		return [] if levels.empty?

		template_signature = Utils.relative_item_path(@template)
		levels.each_with_index.map do |level, depth|
			key = level['key'].to_s
			prefix_levels = levels.first(depth)
			prefix_signature = prefix_levels.map do |prefix_level|
				prefix_key = prefix_level['key'].to_s
				prefix_value = entry.dig('values', prefix_key).to_s
				"#{prefix_key}=#{prefix_value}"
			end.join('|')

			set_signature = [template_signature, layout_name.to_s, depth, key, prefix_signature].join('|')
			set_id = "template-group-set-#{Digest::MD5.hexdigest(set_signature)}"

			{
				'set_id' => set_id,
				'depth' => depth + 1,
				'key' => key,
				'order' => level['order'].to_i,
				'start' => level['start'],
				'end' => level['end'],
				'other' => !!level['other'],
				'range' => !!level['range']
			}
		end
	end

	# Builds canonical page-template settings for page 1 and page 2+.
	def build_page_templates(page2_title, page2_permalink)
		{
			'page1' => {
				'title' => ':title',
				'permalink' => ''
			},
			'page2' => {
				'title' => page2_title.to_s,
				'permalink' => page2_permalink.to_s
			}
		}
	end

	# Applies grouped placeholder tokens to configured page templates while
	# preserving any custom v1/v2 compatibility overrides.
	def tokenised_page_templates(raw_page_templates, token_maps, fallback_title:, fallback_permalink:, replace_page2_permalink_tokens: true)
		page_templates = Utils.safe_hash(raw_page_templates)
		if page_templates.empty?
			page_templates = build_page_templates(fallback_title, fallback_permalink)
		end

		%w[page1 page2].each do |key|
			template = Utils.safe_hash(page_templates[key])
			template['title'] = Utils.replace_tokens(template['title'], token_maps['title']) if template['title'].is_a?(String)
			if template['permalink'].is_a?(String)
				template['permalink'] = Utils.replace_tokens(template['permalink'], token_maps['permalink']) if key != 'page2' || replace_page2_permalink_tokens
			end
			page_templates[key] = template
		end

		page_templates
	end

	# Replaces template data for both pages and documents.
	def replace_template_data!(template, data)
		replacement = Jekyll::Utils.deep_merge_hashes(Utils.safe_hash(data), {})
		if template.respond_to?(:data=)
			template.data = replacement
		elsif template.instance_variable_defined?(:@data)
			template.instance_variable_set(:@data, replacement)
		elsif template.respond_to?(:data)
			template.data.clear
			template.data.merge!(replacement)
		end
	end

	# Slugifies grouped placeholder values according to template config.
	def slugify_value(value, slugify_config:)
		mode = slugify_config['mode'].to_s.strip
		mode = 'default' if mode.empty?
		lowercase = !!slugify_config['lowercase']
		Jekyll::Utils.slugify(value.to_s, mode: mode, cased: !lowercase)
	end

	# Returns true when a config value should be treated as explicitly set.
	def present_config_value?(value)
		return false if value.nil?
		return false if value.is_a?(String) && value.strip.empty?
		return false if value.is_a?(Array) && value.empty?
		return false if value.is_a?(Hash) && value.empty?

		true
	end
end

end
end
end
end
