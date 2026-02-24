# frozen_string_literal: true

module Jekyll
module Plugins
module PaginateV3
module Templates
class Builder
	# Index-entry construction helpers for generated template definitions.
	# Structure: entries are built depth-first per index key, optionally with
	# grouped-index adapters, and emitted as filter/value/token payloads.

	private
	def build_index_entries(items, definition)
		entries = []
		recurse_build_entries(items, definition, 0, {}, {}, {}, [], entries)
		add_empty_collection_entries(entries, definition)
	end

	# Depth-first grouping for multi-level indexes such as
	# `index: category, subcategory`.
	def recurse_build_entries(items, definition, depth, active_filters, active_values, active_token_values, active_levels, entries)
		index_keys = definition['index']
		# Terminal condition: once all index keys are consumed, emit one entry.
		if depth >= index_keys.length
			entries << {
				'filters' => Utils.deep_copy(active_filters),
				'values' => Utils.deep_copy(active_values),
				'token_values' => Utils.deep_copy(active_token_values),
				'levels' => Utils.deep_copy(active_levels)
			}
			return
		end

		key = index_keys[depth]
		grouped_items = groups_for_key(items, key, definition, slugify_config: definition['slugify'])

		grouped_items.each_with_index do |group, group_index|
			# Blank tokens cannot be used in permalinks or placeholder substitution.
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
				definition,
				depth + 1,
				next_filters,
				next_values,
				next_token_values,
				next_levels,
				entries
			)
		end
	end

	# Resolves grouping for one index key from either grouped-range config
	# or ordinary unique-value grouping.
	def groups_for_key(items, key, definition, slugify_config:)
		if definition['group_by_key'].key?(key)
			grouped_entries_for_key(items, key, definition)
		else
			group_items_by_key(items, key, slugify_config: slugify_config).each_with_index.map do |group, index|
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

	# Expands grouped-range entries for one key.
	def grouped_entries_for_key(items, key, definition)
		raw_group = definition['group_by_key'][key]
		fallback_group = definition['group_fallback_by_key'][key]

		grouped_entries = begin
			build_grouped_entries_for_raw(key, raw_group, items)
		rescue ArgumentError
			# If the primary grouped config is invalid, use the configured fallback.
			raise if fallback_group.nil?

			build_grouped_entries_for_raw(key, fallback_group, items)
		end

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

	# Builds grouped-range entries for one key from one raw config block.
	def build_grouped_entries_for_raw(key, raw_group, items)
		grouped = GroupedIndex.new(
			key: key,
			raw_group: raw_group,
			items: items,
			nested_separator: @nested_separator,
			split_delimiter: @split_delimiter,
			equivalents: @equivalents,
			now_keyword: @site_config.dig('keywords', 'now'),
			today_keyword: @site_config.dig('keywords', 'today'),
			keywords: @site_config['keywords'],
			log_lambda: @log_lambda
		)
		grouped.build_entries
	end

	# Groups items by one frontmatter key (supports nested/equivalent keys).
	def group_items_by_key(items, key, slugify_config:)
		equivalent_lookup = Utils.build_equivalent_lookup(@equivalents)
		grouped = {}

		items.each do |item|
			values = values_for_key(item, key, equivalent_lookup)
			values.each do |value|
				token = slugify_value(value, slugify_config)
				# Empty slugs are ignored so generated routes remain valid.
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

	# Extracts unique scalar values for a key, including delimiter-defined
	# string lists.
	def values_for_key(item, key, equivalent_lookup)
		data = item.respond_to?(:data) && item.data.is_a?(Hash) ? item.data.dup : {}
		collection_label = Utils.item_collection_label(item)
		data['collection'] = collection_label unless collection_label.nil?

		values = Utils.fetch_nested_values(data, key, @nested_separator, equivalent_lookup)
		values = values.flat_map do |value|
			if value.is_a?(String)
				Utils.split_delimited_string(value, @split_delimiter)
			else
				Utils.scalar_values(value)
			end
		end

		values.map { |value| value.to_s.strip }.reject(&:empty?).uniq
	end

	# Normalises one raw `templates.generate` definition into a predictable
end
end
end
end
end
