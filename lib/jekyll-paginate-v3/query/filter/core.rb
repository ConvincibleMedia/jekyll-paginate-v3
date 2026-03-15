# frozen_string_literal: true

module Jekyll
module Plugins
module PaginateV3
module Query

# Filtering engine for pagination and generated index discovery.
#
# Public filter definitions are normalised into a single recursive group
# shape:
# - `{ include: [...], exclude: [...], join: and|or }`
#
# Shorthand forms (scalar, range, array, delimited string, scalar hash)
# are all converted into this group model so evaluation follows one
# consistent code path.
class Filter

	# Class helper that instantiates a configured engine per call.
	def self.filter_items(items, filters, nested_separator:, equivalents:, split_delimiter: ',', now_keyword: 'now', today_keyword: 'today', log_lambda: nil, context_label: nil)
		engine = new(
			nested_separator: nested_separator,
			equivalents: equivalents,
			split_delimiter: split_delimiter,
			now_keyword: now_keyword,
			today_keyword: today_keyword,
			log_lambda: log_lambda
		)
		engine.filter_items(items, filters, context_label: context_label)
	end

	# Human-readable formatter used in logs/debug output.
	def self.filter_to_s(filter, split_delimiter: ',', now_keyword: 'now', today_keyword: 'today')
		formatter = new(
			nested_separator: '.',
			equivalents: [],
			split_delimiter: split_delimiter,
			now_keyword: now_keyword,
			today_keyword: today_keyword
		)

		normalised = formatter.send(:normalise_filter, filter)
		return '[invalid filter]' if normalised == false

		formatter.send(:filter_to_s_internal, normalised)
	end

	# Builds an engine configured for nested key and equivalent-key rules.
	def initialize(nested_separator:, equivalents:, split_delimiter:, now_keyword:, today_keyword:, log_lambda: nil)
		@nested_separator = nested_separator
		@split_delimiter = Utils.normalise_split_delimiter(split_delimiter, ',')
		@now_keyword = now_keyword.to_s.strip
		@now_keyword = 'now' if @now_keyword.empty?
		@today_keyword = today_keyword.to_s.strip
		@today_keyword = 'today' if @today_keyword.empty?
		@frontmatter_path = Jekyll::Plugins::Support::FrontmatterPath.new(
			separator: @nested_separator,
			arrays: :expand,
			equivalents: equivalents
		)
		@string_array = Jekyll::Plugins::Support::StringArray.new(delimiter: @split_delimiter)
		@log_lambda = log_lambda
	end

	# Applies all configured filters sequentially (logical AND across keys).
	def filter_items(items, filters, context_label: nil)
		unless filters.is_a?(Hash)
			log_debug("#{filter_context_prefix(context_label)}No valid filter hash provided; retaining #{items.length} item(s).")
			return items
		end

		current_items = items
		Utils.safe_hash(filters).each do |raw_key, raw_filter|
			normalised = normalise_filter(raw_filter)
			key = raw_key.to_s
			if normalised == false
				log_warning("#{filter_context_prefix(context_label)}Ignoring invalid filter for key='#{key}': #{raw_filter.inspect}.")
				next
			end

			filtered_items = []
			missing_value_items = []
			excluded_items = []

			current_items.each do |item|
				value = extract_item_value(item, key)
				if value.nil?
					missing_value_items << item
					next
				end

				if check_filter_definition(normalised, value)
					filtered_items << item
				else
					excluded_items << {
						'item' => item,
						'values' => value
					}
				end
			end

			log_filter_result(
				key: key,
				normalised_filter: normalised,
				total_items: current_items.length,
				filtered_items: filtered_items,
				missing_value_items: missing_value_items,
				excluded_items: excluded_items,
				context_label: context_label
			)
			current_items = filtered_items
		end

		current_items
	end

	private

	# Logs one concise summary line for one applied filter key.
	def log_filter_result(key:, normalised_filter:, total_items:, filtered_items:, missing_value_items:, excluded_items:, context_label:)
		filter_description = filter_to_s_internal(normalised_filter)
		log_debug(
			"#{filter_context_prefix(context_label)}Filter key='#{key}' (#{filter_description}) kept #{filtered_items.length}/#{total_items} item(s); missing_key_or_value=#{missing_value_items.length}; excluded=#{excluded_items.length}."
		)

		log_filter_missing_item_sample(key, missing_value_items, context_label)
		log_filter_excluded_item_sample(key, excluded_items, context_label)
	end

	# Logs a compact sample of items that had no matching filter key/value.
	def log_filter_missing_item_sample(key, items, context_label, limit: 5)
		return if items.empty?

		prefix = filter_context_prefix(context_label)
		maximum = [limit.to_i, 1].max
		sample_paths = items.first(maximum).map { |item| Utils.relative_item_path(item) }
		extra_count = items.length - sample_paths.length
		extra_suffix = extra_count.positive? ? " (+#{extra_count} more)" : ''
		log_debug("#{prefix}Filter key='#{key}' missing key/value on: #{sample_paths.join(', ')}#{extra_suffix}.")
	end

	# Logs a compact sample of items that had values but failed matching.
	def log_filter_excluded_item_sample(key, entries, context_label, limit: 3)
		return if entries.empty?

		prefix = filter_context_prefix(context_label)
		maximum = [limit.to_i, 1].max
		sample = entries.first(maximum).map do |entry|
			item_path = Utils.relative_item_path(entry['item'])
			values_text = format_filter_log_value(entry['values'])
			"#{item_path}=#{values_text}"
		end
		extra_count = entries.length - sample.length
		extra_suffix = extra_count.positive? ? " (+#{extra_count} more)" : ''
		log_debug("#{prefix}Filter key='#{key}' excluded item sample: #{sample.join(' | ')}#{extra_suffix}.")
	end

	# Adds optional context labels to filter diagnostics.
	def filter_context_prefix(context_label)
		label = context_label.to_s.strip
		return '' if label.empty?

		"#{label}: "
	end

	# Truncates inspected values so debug logs stay compact.
	def format_filter_log_value(value, max_length: 120)
		text = value.inspect
		return text if text.length <= max_length

		"#{text[0, max_length]}..."
	end
end

end
end
end
end
