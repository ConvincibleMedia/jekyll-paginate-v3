# frozen_string_literal: true

module Jekyll
module Plugins

module Support

# Forgiving scalar coercion helpers shared by filtering, grouped-index
# detection, and loose configuration parsing.
#
# Structure: callers can ask for one specific scalar family without
# committing the whole pipeline to one feature's semantics.
module LooseScalar
	# Interprets one value as a strict boolean or a loose `true`/`false`
	# string. Returns `nil` when no boolean meaning can be inferred.
	def self.boolean(value)
		return value if value == true || value == false
		return nil unless value.is_a?(String)

		case value.strip.downcase
		when 'true'
			true
		when 'false'
			false
		else
			nil
		end
	end

	# Interprets one value as an integer or float when possible.
	def self.number(value)
		return value if value.is_a?(Integer) || value.is_a?(Float)
		return nil unless value.is_a?(String)

		stripped = value.strip
		return nil if stripped.empty?
		return stripped.to_i if stripped.match?(/\A[+-]?\d+\z/)
		return stripped.to_f if stripped.match?(/\A[+-]?\d+\.\d+\z/)

		nil
	end

	# Reports whether one value is numeric with no fractional component.
	def self.integral_number?(value)
		numeric_value = number(value)
		return false if numeric_value.nil?
		return true if numeric_value.is_a?(Integer)

		(numeric_value % 1).zero?
	end

	# Interprets one value as a datetime in the same loose way used by
	# filter range comparisons.
	def self.datetime(value)
		return value if value.is_a?(DateTime)
		return value.to_datetime if value.is_a?(Time)
		return value.to_datetime if value.is_a?(Date)
		return nil unless value.is_a?(String)

		stripped = value.strip
		return nil if stripped.empty?

		DateTime.parse(stripped)
	rescue ArgumentError
		nil
	end

	# Alias retained because public filter config uses `date` language.
	def self.date(value)
		datetime(value)
	end

	# Converts one value into the loose comparable scalar form used by
	# filtering. Strings become numbers or datetimes when possible, or a
	# stripped string otherwise.
	def self.comparable(value, must_cast: false)
		return value if value.is_a?(Integer) || value.is_a?(Float) || value.is_a?(DateTime)
		return value.to_datetime if value.is_a?(Time)
		return value.to_datetime if value.is_a?(Date)

		unless value.is_a?(String)
			return nil if must_cast

			return value
		end

		stripped = value.strip

		numeric_value = number(stripped)
		return numeric_value unless numeric_value.nil?

		datetime_value = datetime(stripped)
		return datetime_value unless datetime_value.nil?

		return nil if must_cast

		stripped
	end

	# Safe comparability check for mixed scalar types.
	def self.comparable_values?(left, right)
		return true if left.class == right.class
		return true if (left.is_a?(Integer) || left.is_a?(Float)) && (right.is_a?(Integer) || right.is_a?(Float))

		!((left <=> right).nil?)
	rescue ArgumentError, NoMethodError
		false
	end
end

end

end
end
