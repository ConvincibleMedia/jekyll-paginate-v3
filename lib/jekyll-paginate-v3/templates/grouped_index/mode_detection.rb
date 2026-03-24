# frozen_string_literal: true

module Jekyll
module Plugins
module PaginateV3
module Templates

# Grouped-index mode detection and candidate interpretation helpers.
# Structure: explicit config hints are checked first, then item values are
# sampled to infer numeric, datetime, or alphabetic grouping mode.
class GroupedIndex

	private
	
	def normalise_keyword(raw_keyword, fallback)
		keyword = raw_keyword.to_s.strip
		keyword.empty? ? fallback : keyword
	end

	# Builds configured keyword mapping for duration units used by
	# datetime grouped indexing.
	def build_duration_keyword_map(raw_keywords)
		keywords = Utils.safe_hash(raw_keywords)

		DURATION_UNITS.each_with_object({}) do |unit, memo|
			memo[unit] = normalise_keyword(keywords[unit], unit).downcase
		end
	end

	# Returns regex alternation for configured duration keywords.
	def duration_keywords_pattern
		@duration_keywords_pattern ||= @duration_keyword_by_unit.values.map { |keyword| Regexp.escape(keyword) }.join('|')
	end

	# Resolves one configured duration keyword back to canonical unit name.
	def canonical_duration_unit(keyword)
		@duration_unit_by_keyword[keyword.to_s.strip.downcase]
	end

	# Chooses grouping mode using config-first hints and then candidate
	# value sampling when config alone is ambiguous.
	def resolve_grouping_mode
		# Explicit config always wins over inferred data sampling.
		hinted_mode = explicit_mode_hint
		return hinted_mode unless hinted_mode.nil?

		# Fall back to observed values when config is intentionally generic.
		inferred_mode = inferred_mode_from_item_values
		return inferred_mode unless inferred_mode.nil?

		# Numeric is the final safe default for range grouping.
		'numeric'
	end

	# Attempts to detect an explicit grouping mode directly from `group`.
	def explicit_mode_hint
		case @raw_group
		when Hash
			hash_group = Utils.safe_hash(@raw_group)
			return 'datetime' if datetime_group_hash_hint?(hash_group)
			start_value = hash_group['start']
			return 'alphabetic' if alphabetic_start_token?(start_value)
			return 'alphabetic' if hash_group.key?('other')
		when String
			value = @raw_group.strip
			return nil if value.empty?
			return 'datetime' if duration_token?(value) || datetime_anchor_token?(value) || datetime_keyword_expression?(value)
			return 'numeric' if numeric_string?(value)
			return 'alphabetic' if alphabetic_start_token?(value)
		when Integer, Float
			# Pure numeric shorthand (`group: 10`) is valid for both numeric and
			# datetime modes, so keep mode unresolved here.
			return nil
		end

		nil
	end

	# Determines whether a hash-group config appears datetime-oriented.
	def datetime_group_hash_hint?(hash_group)
		%w[start step min max].any? do |key|
			value = hash_group[key]
			next false if value.nil?

			datetime_hint_value?(value)
		end
	end

	# Detects whether one config value strongly hints datetime mode.
	def datetime_hint_value?(value)
		if value.is_a?(Array)
			return value.any? { |entry| datetime_hint_value?(entry) }
		end

		if value.is_a?(String)
			stripped = value.strip
			return false if stripped.empty?
			return true if duration_token?(stripped)
			return true if datetime_anchor_token?(stripped)
			return true if datetime_keyword_expression?(stripped)
			return false if numeric_string?(stripped)
			return !interpret_datetime_value(stripped).nil?
		end

		value.is_a?(Date) || value.is_a?(DateTime) || value.is_a?(Time)
	end

	# Uses extracted item values to infer grouping mode when not explicit.
	def inferred_mode_from_item_values
		counts = {
			'numeric' => 0,
			'datetime' => 0,
			'alphabetic' => 0
		}

		prepare_candidates(@items).each do |candidate|
			counts['numeric'] += 1 unless candidate['numeric'].nil?
			counts['datetime'] += 1 unless candidate['datetime'].nil?
			counts['alphabetic'] += 1 if candidate['alpha_starts_with_letter']
		end

		highest_count = counts.values.max
		return nil if highest_count.nil? || highest_count.zero?

		# Deterministic tie-break keeps behaviour stable across runs.
		preferred_order = %w[numeric datetime alphabetic]
		preferred_order.each do |mode|
			return mode if counts[mode] == highest_count
		end

		nil
	end

	# Extracts parse-ready candidates for numeric, datetime, and
	# alphabetic interpretation per item. Each item contributes at most one
	# effective value in any specific mode.
	def prepare_candidates(items)
		items.map do |item|
			raw_values = raw_values_for_key(item)

			numeric_value = nil
			datetime_value = nil
			alpha_value = nil
			alpha_starts_with_letter = false

			raw_values.each do |raw_value|
				numeric_value = interpret_numeric_value(raw_value) if numeric_value.nil?
				datetime_value = interpret_datetime_value(raw_value) if datetime_value.nil?

				if alpha_value.nil?
					alpha_candidate = normalise_alpha_value(raw_value)
					alpha_value = alpha_candidate['letters']
					alpha_starts_with_letter = alpha_candidate['starts_with_letter']
				end

				# Stop once each mode has one usable candidate for this item.
				break unless numeric_value.nil? || datetime_value.nil? || alpha_value.nil?
			end

			{
				'item' => item,
				'raw_values' => raw_values,
				'numeric' => numeric_value,
				'datetime' => datetime_value,
				'alpha' => alpha_value,
				'alpha_starts_with_letter' => alpha_starts_with_letter
			}
		end
	end

	# Reads scalar values for one key from frontmatter, including nested
	# and equivalent-key resolution. String values are split by configured
	# delimiter to mirror other query semantics.
	def raw_values_for_key(item)
		data = item.respond_to?(:data) && item.data.is_a?(Hash) ? item.data.dup : {}
		collection_label = Utils.item_collection_label(item)
		data['collection'] = collection_label unless collection_label.nil?

		Utils.scalar_values(@frontmatter_path.traverse(data, @key)).flat_map do |value|
			if value.is_a?(String)
				split_values = @string_array.interpret(value, split: 0, flatten: true)
				split_values.empty? ? [value] : split_values
			else
				[value]
			end
		end.reject do |value|
			value.nil? || (value.respond_to?(:empty?) && value.empty?)
		end
	end

	# Parses numeric candidates using the same integer/float rules as
	# filter range parsing.
	def interpret_numeric_value(value)
		numeric_value = Jekyll::Plugins::PaginateV3::Support::LooseScalar.number(value)
		numeric_value.nil? ? nil : numeric_value.to_f
	end

	# Parses datetime candidates from Date/Time values or parseable
	# datetime strings.
	def interpret_datetime_value(value)
		Jekyll::Plugins::PaginateV3::Support::LooseScalar.datetime(value)
	end

	# Normalises one value for alphabetic comparison:
	# - stringified
	# - downcased
	# - best-effort transliteration to ASCII
	# - letters-only token for grouping
	def normalise_alpha_value(value)
		string_value = value.to_s
		transliterated = string_value.unicode_normalize(:nfkd).encode('ASCII', invalid: :replace, undef: :replace, replace: '').downcase
		starts_with_letter = transliterated.match?(/\A[a-z]/)
		letters = transliterated.gsub(/[^a-z]/, '')

		{
			'letters' => letters,
			'starts_with_letter' => starts_with_letter
		}
	rescue StandardError
		{
			'letters' => '',
			'starts_with_letter' => false
		}
	end

	# Detects whether a value can be used as an alphabetic start token.
	def alphabetic_start_token?(value)
		return false unless value.is_a?(String)

		normalised = normalise_alpha_value(value)
		normalised['starts_with_letter'] && !normalised['letters'].empty?
	end

	# Detects duration-like expressions such as `month(2)`.
	def duration_token?(value)
		return false unless value.is_a?(String)

		value.strip.match?(/\A(?:#{duration_keywords_pattern})(?:\s*\(.*\))?\z/i)
	end

	# Detects anchor expressions such as `month(today)` or `hour(now)`.
	def datetime_anchor_token?(value)
		return false unless value.is_a?(String)

		stripped = value.strip
		match = stripped.match(/\A(#{duration_keywords_pattern})\s*\((.+)\)\z/i)
		return false if match.nil?

		inner = match[2].to_s.strip
		datetime_keyword_expression?(inner)
	end

	# Detects `now` / `today` keyword expressions with optional offsets.
	def datetime_keyword_expression?(value)
		return false unless value.is_a?(String)

		stripped = value.strip
		keyword_patterns = [Regexp.escape(@now_keyword), Regexp.escape(@today_keyword)]
		stripped.match?(/\A(?:#{keyword_patterns.join('|')})(?:\s*[+-]\s*\d+)?\z/i)
	end

	# Detects integer/float string forms.
	def numeric_string?(value)
		value.to_s.strip.match?(/\A[+-]?\d+(?:\.\d+)?\z/)
	end

end

end
end
end
end
