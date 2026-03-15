# frozen_string_literal: true

module Jekyll
module Plugins
module PaginateV3
module Query

# Filter-evaluation helpers for matching item values against normalised
# filter definitions. Structure: values are extracted, each filter node is
# evaluated recursively, then include/exclude joins are combined.
class Filter

	private

	# Extracts one resolved frontmatter value for one filter key.
	# Includes synthetic `collection` for parity with query/sort behaviour.
	#
	# Arrays are flattened so scalar modes no longer care whether a list
	# originated from one array field or from several traversed matches.
	def extract_item_value(item, key)
		data = item.respond_to?(:data) && item.data.is_a?(Hash) ? item.data : {}
		decorated_data = data.dup

		collection_label = Utils.item_collection_label(item)
		decorated_data['collection'] = collection_label unless collection_label.nil?

		resolved_value = @frontmatter_path.traverse(decorated_data, key)
		return nil if empty_filter_value?(resolved_value)

		return resolved_value.flatten.compact.reject { |value| empty_filter_value?(value) } if resolved_value.is_a?(Array)

		resolved_value
	end

	# Evaluates one normalised filter definition node.
	def check_filter_definition(definition, item_value)
		if group_definition?(definition)
			check_group_filter(definition, item_value)
		elsif scalar_definition?(definition)
			check_scalar_filter(definition, item_value)
		elsif range_definition?(definition)
			scalar_candidates_from_item_value(item_value).any? { |value| range_match?(value, definition['min'], definition['max'], definition['mode']) }
		else
			false
		end
	end

	# Evaluates include/exclude group logic.
	def check_group_filter(group_definition, item_value)
		join_mode = group_definition['join'] || 'or'

		include_results = group_definition['include'].map { |entry| check_filter_definition(entry, item_value) }
		include_pass = include_results.empty? ? true : combine_join_results(include_results, join_mode)

		exclude_results = group_definition['exclude'].map { |entry| check_filter_definition(entry, item_value) }
		exclude_match = exclude_results.empty? ? false : combine_join_results(exclude_results, join_mode)

		include_pass && !exclude_match
	end

	# Combines boolean results under one join mode.
	def combine_join_results(results, join_mode)
		join_mode == 'and' ? results.all? : results.any?
	end

	# Flattens the resolved value to scalars for non-scalar-specific checks.
	# No automatic string splitting is applied.
	def scalar_candidates_from_item_value(item_value)
		Utils.scalar_values(item_value).reject { |value| empty_filter_value?(value) }
	end

	# Evaluates scalar comparison rules against one resolved item value.
	# - strict: `==` only
	# - auto: `==` and includes on arrays
	# - only: includes only for single-item arrays
	# - first: compares only against the first N array entries
	def check_scalar_filter(filter_definition, item_value)
		match_value = filter_definition['match']
		match_mode = filter_definition['mode'] || 'auto'
		split_definition = filter_definition['split']
		first_count = filter_definition['first']

		comparable_value = apply_scalar_split(item_value, split_definition)
		scalar_value_matches?(comparable_value, match_value, match_mode, first_count)
	end

	# Applies configured scalar split behaviour to one item value.
	def apply_scalar_split(value, split_definition)
		return value if split_definition == false

		delimiter = split_definition.is_a?(String) ? split_definition : @split_delimiter
		@string_array.interpret(value, split: -1, flatten: true, delimiter: delimiter)
	end

	# Evaluates one prepared item value against one scalar definition.
	def scalar_value_matches?(item_value, match_value, match_mode, first_count = nil)
		if match_mode == 'first'
			return value_matches_scalar_definition?(item_value, match_value) unless item_value.is_a?(Array)

			compare_count = [first_count.to_i, 1].max
			return item_value.first(compare_count).any? { |entry| value_matches_scalar_definition?(entry, match_value) }
		end

		direct_match = value_matches_scalar_definition?(item_value, match_value)
		return direct_match if match_mode == 'strict'
		return true if direct_match
		return false unless item_value.is_a?(Array)
		return false if match_mode == 'only' && item_value.length != 1

		item_value.any? { |entry| value_matches_scalar_definition?(entry, match_value) }
	end

	# Compares one scalar value against one scalar match definition.
	def value_matches_scalar_definition?(value, match_value)
		if match_value.is_a?(Regexp)
			return false if value.is_a?(Array) || value.is_a?(Hash)

			return match_value.match?(value.to_s)
		end

		comparable_value = normalise_comparable_scalar(value)
		comparable_value == match_value
	end

	# Checks one item value against an optional min/max range.
	def range_match?(value, min_value, max_value, range_mode)
		comparable_value = normalise_comparable_scalar(value)
		return false if comparable_value.nil?

		min_inclusive, max_inclusive = parse_range_mode_flags(range_mode)

		if !min_value.nil?
			return false unless values_comparable?(comparable_value, min_value)
			if min_inclusive
				return false if comparable_value < min_value
			else
				return false if comparable_value <= min_value
			end
		end

		if !max_value.nil?
			return false unless values_comparable?(comparable_value, max_value)
			if max_inclusive
				return false if comparable_value > max_value
			else
				return false if comparable_value >= max_value
			end
		end

		true
	rescue ArgumentError, NoMethodError
		false
	end

	# Parses one canonical range mode string into inclusion flags.
	def parse_range_mode_flags(range_mode)
		mode_text = range_mode.to_s
		min_inclusive = !mode_text.include?('min-exclusive')
		max_inclusive = !mode_text.include?('max-exclusive')
		[min_inclusive, max_inclusive]
	end

	# Safe comparability check for mixed scalar types.
	def values_comparable?(left, right)
		return true if left.class == right.class
		return true if (left.is_a?(Integer) || left.is_a?(Float)) && (right.is_a?(Integer) || right.is_a?(Float))

		!((left <=> right).nil?)
	rescue ArgumentError, NoMethodError
		false
	end

	# Detects whether one resolved filter value should be treated as absent.
	def empty_filter_value?(value)
		value.nil? || (value.respond_to?(:empty?) && value.empty?)
	end

	# Emits a warning message through the optional logger callback.
	def log_warning(message)
		return if @log_lambda.nil?

		@log_lambda.call(message, 'warn')
	end

	# Emits a debug message through the optional logger callback.
	def log_debug(message)
		return if @log_lambda.nil?

		@log_lambda.call(message, 'debug')
	end
end

end
end
end
end
