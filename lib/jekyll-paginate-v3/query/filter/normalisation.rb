# frozen_string_literal: true

module Jekyll
module Plugins
module PaginateV3
module Query

# Filter-normalisation helpers that convert public filter shorthand into
# one canonical internal tree model. Structure: each supported shorthand
# form is parsed and wrapped into consistent scalar/range/group nodes.
class Filter

	private

	def normalise_filter(filter)
		normalised = normalise_filter_definition(filter)
		return false if normalised == false
		return normalised if group_definition?(normalised)

		# Non-group shorthand is wrapped so downstream evaluation only needs
		# to process one canonical group shape.
		wrap_as_or_group([normalised])
	end

	# Normalises one filter definition node.
	def normalise_filter_definition(definition)
		case definition
		when Hash
			normalise_filter_hash(definition)
		when Array
			normalise_shortcut_array(definition)
		when String
			normalise_shortcut_string(definition)
		when Regexp, Integer, Float, Date, DateTime, Time
			normalise_scalar_shortcut(definition)
		else
			false
		end
	end

	# Routes hash definitions to group/scalar/range handlers.
	def normalise_filter_hash(definition)
		hash_definition = Utils.stringify_keys(definition)

		# Route by intent: longhand group, scalar match, then range.
		if group_hash?(hash_definition)
			normalise_group_hash(hash_definition)
		elsif hash_definition.key?('match')
			normalise_scalar_hash(hash_definition)
		elsif hash_definition.key?('min') || hash_definition.key?('max')
			normalise_range_hash(hash_definition)
		else
			false
		end
	end

	# Detects group definitions by longhand keys.
	def group_hash?(hash_definition)
		hash_definition.key?('include') || hash_definition.key?('exclude')
	end

	# Normalises longhand grouped definitions.
	def normalise_group_hash(hash_definition)
		include_entries = []
		if hash_definition.key?('include')
			parsed_include = normalise_group_entries(hash_definition['include'])
			return false if parsed_include == false

			include_entries.concat(parsed_include)
		end

		exclude_entries = []
		if hash_definition.key?('exclude')
			parsed_exclude = normalise_group_entries(hash_definition['exclude'])
			return false if parsed_exclude == false

			exclude_entries.concat(parsed_exclude)
		end

		return false if include_entries.empty? && exclude_entries.empty?

		{
			'include' => include_entries,
			'exclude' => exclude_entries,
			'join' => normalise_join(hash_definition['join'])
		}
	end

	# Normalises include/exclude members. Each member is itself a filter
	# definition instance and is normalised recursively.
	def normalise_group_entries(raw_entries)
		entries = normalise_delimited_entries(raw_entries)
		return false unless entries.is_a?(Array)

		normalised_entries = entries.map { |entry| normalise_filter_definition(entry) }.reject { |entry| entry == false }
		return false if normalised_entries.empty?

		normalised_entries
	end

	# Normalises array shorthand as `include: <entries>, join: or`.
	def normalise_shortcut_array(raw_entries)
		entries = raw_entries.flatten.compact
		return false if entries.empty?

		normalised_entries = entries.map { |entry| normalise_filter_definition(entry) }.reject { |entry| entry == false }
		return false if normalised_entries.empty?

		wrap_as_or_group(normalised_entries)
	end

	# Normalises scalar string shorthand.
	# Delimited strings become an `or` group of scalar shortcuts.
	def normalise_shortcut_string(raw_value)
		split_values = Utils.split_delimited_string(raw_value.to_s, @split_delimiter)
		return false if split_values.empty?

		if split_values.length == 1
			return normalise_scalar_shortcut(split_values.first)
		end

		normalised_entries = split_values.map { |value| normalise_scalar_shortcut(value) }.reject { |entry| entry == false }
		return false if normalised_entries.empty?

		wrap_as_or_group(normalised_entries)
	end

	# Scalar shortcut:
	# `{ match: <scalar>, mode: auto, split: true }`.
	# Split `true` resolves to the configured global split delimiter.
	def normalise_scalar_shortcut(raw_value)
		scalar_match = normalise_scalar_match_value(raw_value)
		return false if scalar_match == false

		{
			'match' => scalar_match,
			'mode' => 'auto',
			'split' => @split_delimiter
		}
	end

	# Normalises scalar hash filters (`match`, `mode`, `split`, `first`).
	def normalise_scalar_hash(hash_definition)
		scalar_match = normalise_scalar_match_value(hash_definition['match'])
		return false if scalar_match == false

		raw_mode = hash_definition.key?('mode') ? hash_definition['mode'] : hash_definition['type']
		scalar_mode, embedded_first_count = normalise_scalar_match_mode(raw_mode)
		return false if scalar_mode == false

		scalar_split = normalise_scalar_split(hash_definition['split'])
		return false if scalar_split == :invalid

		normalised = {
			'match' => scalar_match,
			'mode' => scalar_mode,
			'split' => scalar_split
		}

		if scalar_mode == 'first'
			scalar_first_count = normalise_scalar_first_count(hash_definition['first'], embedded_first_count)
			return false if scalar_first_count == :invalid

			normalised['first'] = scalar_first_count
		end

		normalised
	end

	# Normalises scalar match values, including regex literal strings.
	def normalise_scalar_match_value(value)
		if value.is_a?(String)
			parse_scalar(value.strip)
		elsif value.is_a?(Regexp) || value.is_a?(Integer) || value.is_a?(Float) || value.is_a?(Date) || value.is_a?(DateTime) || value.is_a?(Time)
			normalise_comparable_scalar(value)
		else
			false
		end
	end

	# Normalises scalar hash match mode (`strict`, `auto`, `only`,
	# `first`, `first(N)`).
	#
	# Returns:
	# - `[mode, embedded_first_count]`
	# - `false` when invalid.
	def normalise_scalar_match_mode(raw_mode)
		mode_value = raw_mode.to_s.strip.downcase
		mode_value = 'auto' if mode_value.empty?

		return [mode_value, nil] if %w[strict auto only].include?(mode_value)
		return ['first', nil] if mode_value == 'first'

		bracket_first_match = mode_value.match(/\Afirst\(\s*(\d+)\s*\)\z/)
		return ['first', bracket_first_match[1].to_i] unless bracket_first_match.nil?

		false
	end

	# Normalises the `first` count used by `mode: first`.
	# Defaults to 1 when not supplied.
	def normalise_scalar_first_count(raw_first, embedded_default = nil)
		return embedded_default if !embedded_default.nil? && embedded_default.positive?

		return 1 if raw_first.nil?

		if raw_first.is_a?(Integer)
			return raw_first if raw_first.positive?

			return :invalid
		end

		if raw_first.is_a?(Float)
			return raw_first.to_i if raw_first.positive? && (raw_first % 1).zero?

			return :invalid
		end

		return :invalid unless raw_first.is_a?(String)

		stripped = raw_first.strip
		return :invalid if stripped.empty?

		return stripped.to_i if stripped.match?(/\A\d+\z/) && stripped.to_i.positive?

		:invalid
	end

	# Normalises scalar split configuration.
	# - nil / true => global split delimiter
	# - false => disable splitting
	# - non-empty string => explicit delimiter override
	def normalise_scalar_split(raw_split)
		return @split_delimiter if raw_split.nil?
		return @split_delimiter if raw_split == true
		return false if raw_split == false

		return :invalid unless raw_split.is_a?(String)

		lowered = raw_split.strip.downcase
		return @split_delimiter if lowered == 'true'
		return false if lowered == 'false'

		return :invalid if raw_split.empty?

		raw_split
	end

	# Normalises range hash filters (`min`, `max`).
	def normalise_range_hash(hash_definition)
		range_hash = hash_definition.select { |key, _| %w[min max mode].include?(key) }
		return false unless range_hash.key?('min') || range_hash.key?('max')

		%w[min max].each do |range_key|
			next unless range_hash.key?(range_key)

			parsed_value = interpret_numeric_or_date_keyword(range_hash[range_key], range_key: range_key)
			return false if parsed_value == false

			range_hash[range_key] = parsed_value
		end

		return false if range_hash['min'].nil? && range_hash['max'].nil?

		if !range_hash['min'].nil? && !range_hash['max'].nil?
			min_value = range_hash['min']
			max_value = range_hash['max']

			# Coerce comparable types before we validate ordering.
			if numeric?(min_value) && numeric?(max_value)
				min_value = min_value.to_f
				max_value = max_value.to_f
			elsif date_like?(min_value) && date_like?(max_value)
				min_value = normalise_comparable_scalar(min_value)
				max_value = normalise_comparable_scalar(max_value)
			elsif min_value.class != max_value.class
				return false
			end

			if min_value > max_value
				log_warning("Range filter has min greater than max (#{min_value} > #{max_value}); swapping the bounds.")
				min_value, max_value = max_value, min_value
			end

			range_hash['min'] = min_value
			range_hash['max'] = max_value
		end

		normalised_mode = normalise_range_mode(
			range_hash['mode'],
			has_min: !range_hash['min'].nil?,
			has_max: !range_hash['max'].nil?
		)
		return false if normalised_mode == :invalid

		range_hash['mode'] = normalised_mode

		range_hash
	end

	# Normalises range match mode while preserving inclusive defaults.
	#
	# Supported mode fragments:
	# - `min-inclusive` / `min-exclusive`
	# - `max-inclusive` / `max-exclusive`
	# - `inclusive` (both inclusive)
	# - `exclusive` (both exclusive)
	#
	# Modes can be combined as whitespace-separated fragments.
	def normalise_range_mode(raw_mode, has_min:, has_max:)
		if raw_mode.nil? || raw_mode.to_s.strip.empty?
			return default_range_mode(has_min: has_min, has_max: has_max)
		end

		min_inclusive = true
		max_inclusive = true
		mode_tokens = raw_mode.to_s.strip.downcase.split(/\s+/)
		return :invalid if mode_tokens.empty?

		mode_tokens.each do |token|
			# Later tokens may intentionally override earlier inclusivity flags.
			case token
			when 'inclusive'
				min_inclusive = true
				max_inclusive = true
			when 'exclusive'
				min_inclusive = false
				max_inclusive = false
			when 'min-inclusive'
				return :invalid unless has_min

				min_inclusive = true
			when 'min-exclusive'
				return :invalid unless has_min

				min_inclusive = false
			when 'max-inclusive'
				return :invalid unless has_max

				max_inclusive = true
			when 'max-exclusive'
				return :invalid unless has_max

				max_inclusive = false
			else
				return :invalid
			end
		end

		range_mode_fragments = []
		range_mode_fragments << (min_inclusive ? 'min-inclusive' : 'min-exclusive') if has_min
		range_mode_fragments << (max_inclusive ? 'max-inclusive' : 'max-exclusive') if has_max
		range_mode_fragments.join(' ')
	end

	# Builds the canonical default mode for present range endpoints.
	def default_range_mode(has_min:, has_max:)
		mode_fragments = []
		mode_fragments << 'min-inclusive' if has_min
		mode_fragments << 'max-inclusive' if has_max
		mode_fragments.join(' ')
	end

	# Converts grouped entry inputs into an array without blank items.
	# Strings are split by the configured global delimiter.
	def normalise_delimited_entries(raw_entries)
		if raw_entries.is_a?(Array)
			raw_entries.flatten.compact
		elsif raw_entries.is_a?(String)
			Utils.delimited_array(raw_entries, delimiter: @split_delimiter)
		elsif raw_entries.nil?
			[]
		else
			[raw_entries]
		end
	end

	# Wraps a list of entries as a default `or` group.
	def wrap_as_or_group(entries)
		{
			'include' => entries,
			'exclude' => [],
			'join' => 'or'
		}
	end

	# Normalises group join mode.
	def normalise_join(raw_join)
		join_value = raw_join.to_s.strip.downcase
		%w[or and].include?(join_value) ? join_value : 'or'
	end

	# Parses scalar filter values, including regex literals.
	def parse_scalar(value)
		if value =~ %r{\A/(.*?)/([imx]*)\z}
			source = Regexp.last_match(1)
			flags = Regexp.last_match(2)
			options = 0
			options |= Regexp::IGNORECASE if flags.include?('i')
			options |= Regexp::MULTILINE if flags.include?('m')
			options |= Regexp::EXTENDED if flags.include?('x')
			return Regexp.new(source, options)
		end

		interpret_numeric(value)
	end

	# Parses numeric/date range endpoints and supports configurable
	# `keywords.now` and `keywords.today`.
	#
	# Examples (assuming default keywords):
	# - now
	# - now+90
	# - today
	# - today-1
	def interpret_numeric_or_date_keyword(value, range_key: nil)
		if value.is_a?(String)
			# Keywords are checked first so string forms like `today+1` are not
			# misread as ordinary scalar strings.
			now_expression = interpret_now_expression(value)
			return now_expression unless now_expression.nil?

			today_expression = interpret_today_expression(value, range_key: range_key)
			return today_expression unless today_expression.nil?
		end

		interpret_numeric(value, must_cast: true)
	end

	# Parses configured now-keyword expressions into DateTime values.
	# Offsets are in whole seconds.
	def interpret_now_expression(value)
		keyword_pattern = Regexp.escape(@now_keyword)
		expression = value.to_s.strip
		match = expression.match(/\A#{keyword_pattern}(?:\s*([+-])\s*(\d+))?\z/i)
		return nil if match.nil?

		offset_seconds = match[2].nil? ? 0 : match[2].to_i
		offset_seconds = -offset_seconds if match[1] == '-'

		DateTime.now + Rational(offset_seconds, 86_400)
	end

	# Parses configured today-keyword expressions into DateTime values.
	#
	# Offsets are in whole days and the parsed value is normalised to the
	# start or end of the day depending on whether the value is used as a
	# `min` or `max` range endpoint.
	def interpret_today_expression(value, range_key:)
		keyword_pattern = Regexp.escape(@today_keyword)
		expression = value.to_s.strip
		match = expression.match(/\A#{keyword_pattern}(?:\s*([+-])\s*(\d+))?\z/i)
		return nil if match.nil?

		offset_days = match[2].nil? ? 0 : match[2].to_i
		offset_days = -offset_days if match[1] == '-'

		current_time = DateTime.now
		target_date = current_time.to_date + offset_days

		if range_key == 'max'
			DateTime.new(target_date.year, target_date.month, target_date.day, 23, 59, 59, current_time.offset)
		else
			DateTime.new(target_date.year, target_date.month, target_date.day, 0, 0, 0, current_time.offset)
		end
	end

	# Casts string values to Integer, Float, or DateTime when possible.
	# Returns the original string unless strict casting is requested.
	def interpret_numeric(value, must_cast: false)
		return value if value.is_a?(Integer) || value.is_a?(Float)
		return value if value.is_a?(DateTime)
		return value.to_datetime if value.is_a?(Time)
		return value.to_datetime if value.is_a?(Date)

		unless value.is_a?(String)
			return false if must_cast

			return value
		end

		stripped = value.strip
		# In strict mode (`must_cast`), unparseable strings are invalid.
		return stripped.to_i if stripped.match?(/\A[+-]?\d+\z/)
		return stripped.to_f if stripped.match?(/\A[+-]?\d+\.\d+\z/)

		begin
			DateTime.parse(stripped)
		rescue ArgumentError
			return false if must_cast

			stripped
		end
	end

	# Normalises values to a comparable scalar form.
	def normalise_comparable_scalar(value)
		return interpret_numeric(value) if value.is_a?(String)
		return value.to_datetime if value.is_a?(Time)
		return value.to_datetime if value.is_a?(Date) && !value.is_a?(DateTime)

		value
	end

	# Numeric type check used by range coercion.
	def numeric?(value)
		value.is_a?(Integer) || value.is_a?(Float)
	end

	# Date-like type check used by range coercion.
	def date_like?(value)
		value.is_a?(Date) || value.is_a?(DateTime) || value.is_a?(Time)
	end
end

end
end
end
end
