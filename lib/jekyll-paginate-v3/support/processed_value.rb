# frozen_string_literal: true

module Jekyll
module Plugins
module PaginateV3

module Support

# Filter-style value preparation helper shared by existence, scalar, and
# range checks.
#
# Structure: one raw resolved frontmatter value is normalised using the
# active split rules, then presence, type, length, and scalar-candidate
# questions are answered from that prepared value.
class ProcessedValue
	TYPE_ALIASES = {
		'datetime' => 'date'
	}.freeze
	SUPPORTED_TYPES = %w[array string boolean int float date].freeze

	attr_reader :value

	def self.build(raw_value, string_array:, split: true)
		new(raw_value, string_array: string_array, split: split)
	end

	def initialize(raw_value, string_array:, split: true)
		@raw_value = raw_value
		@string_array = string_array
		@split = split
		@value = prepare_value(raw_value)
	end

	# Reports whether the prepared value should be treated as present.
	def present?
		!blank_value?(@value)
	end

	# Reports whether the prepared value is array-shaped.
	def array?
		present? && @value.is_a?(Array)
	end

	# Reports whether the prepared value is string-shaped.
	def string?
		present? && @value.is_a?(String)
	end

	# Returns the array/string length used by length-aware range filters.
	def length
		return nil unless present?
		return @value.length if @value.is_a?(Array) || @value.is_a?(String)

		nil
	end

	# Returns scalar candidates prepared for scalar/range evaluation.
	def scalar_candidates
		return [] unless present?
		return [] if @value.is_a?(Hash)

		if @value.is_a?(Array)
			return @value.flatten.compact.reject { |entry| scalar_blank?(entry) || entry.is_a?(Hash) }
		end

		scalar_blank?(@value) ? [] : [@value]
	end

	# Reports whether the prepared value satisfies one configured exists-type.
	def type?(raw_type)
		type = normalise_type(raw_type)
		return false if type.nil?

		case type
		when 'array'
			array?
		when 'string'
			string?
		else
			return false unless singular_scalar?

			scalar_matches_type?(@value, type)
		end
	end

	private

	# Normalises one raw value using the configured split behaviour while
	# preserving scalar shape when splitting produces only one token.
	def prepare_value(raw_value)
		return nil if raw_value.nil?
		return prepare_array(raw_value) if raw_value.is_a?(Array)
		return prepare_string(raw_value) if raw_value.is_a?(String)

		raw_value
	end

	# Normalises one array by flattening nested arrays and applying the same
	# per-entry split rules used for scalar strings.
	def prepare_array(array)
		array.flatten.compact.each_with_object([]) do |entry, prepared|
			prepared.concat(array_entries_for(entry))
		end
	end

	# Normalises one string using the active delimiter but keeps a scalar
	# string when no real multi-token split occurred.
	def prepare_string(value)
		return value if @split == false

		split_values = @string_array.interpret(value, split: 0, flatten: true, delimiter: active_delimiter)
		return '' if split_values.empty?
		return split_values.first if split_values.length == 1

		split_values
	end

	# Converts one array entry into zero or more prepared entries.
	def array_entries_for(entry)
		return [] if entry.nil?
		return prepare_array(entry) if entry.is_a?(Array)
		return [entry] if @split == false
		return @string_array.interpret(entry, split: 0, flatten: true, delimiter: active_delimiter) if entry.is_a?(String)

		[entry]
	end

	# Detects values that should count as absent at the prepared-value
	# level, including whitespace-only strings.
	def blank_value?(value)
		return true if value.nil?
		return value.strip.empty? if value.is_a?(String)

		value.respond_to?(:empty?) && value.empty?
	end

	# Detects blank scalar candidates while leaving non-scalar containers to
	# the caller.
	def scalar_blank?(value)
		return true if value.nil?
		return value.strip.empty? if value.is_a?(String)

		value.respond_to?(:empty?) && value.empty?
	end

	# Reports whether the prepared value is one usable scalar rather than an
	# array/container.
	def singular_scalar?
		present? && !@value.is_a?(Array) && !@value.is_a?(Hash)
	end

	# Matches one prepared scalar against one supported exists-type.
	def scalar_matches_type?(value, type)
		case type
		when 'boolean'
			!LooseScalar.boolean(value).nil?
		when 'int'
			LooseScalar.integral_number?(value)
		when 'float'
			!LooseScalar.number(value).nil?
		when 'date'
			!LooseScalar.date(value).nil?
		else
			false
		end
	end

	# Normalises one configured exists-type string.
	def normalise_type(raw_type)
		type = raw_type.to_s.strip.downcase
		type = TYPE_ALIASES.fetch(type, type)
		return nil unless SUPPORTED_TYPES.include?(type)

		type
	end

	# Resolves the active split delimiter against the helper default.
	def active_delimiter
		@split.is_a?(String) ? @split : @string_array.delimiter
	end
end

end

end
end
end
