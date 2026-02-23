# frozen_string_literal: true

module Jekyll
  module Plugins
    module PaginateV3
      module Utils
        # Core helpers shared across config, query, and pagination layers.
        #
        # Used broadly by normalisers, builders, and parsers.

        # Deep copy helper for plain Ruby hashes/arrays used in config merging.
        def self.deep_copy(value)
          if value.is_a?(Hash)
            value.each_with_object({}) { |(key, child), copy| copy[key] = deep_copy(child) }
          elsif value.is_a?(Array)
            value.map { |child| deep_copy(child) }
          else
            value
          end
        end

        # Normalises a configurable delimiter.
        # Returns `default_delimiter` when the input is blank or not a string.
        def self.normalise_split_delimiter(raw_delimiter, default_delimiter = ',')
          return default_delimiter unless raw_delimiter.is_a?(String)

          delimiter = raw_delimiter
          delimiter.empty? ? default_delimiter : delimiter
        end

        # Splits one string using the configured delimiter, trims entries, and
        # rejects blank strings.
        def self.split_delimited_string(value, delimiter)
          split_pattern = Regexp.new(Regexp.escape(delimiter.to_s))
          value.to_s.split(split_pattern, -1).map(&:strip).reject(&:empty?)
        end

        # Converts scalars/arrays into a flat array and applies delimited-string
        # expansion for all string entries.
        def self.delimited_array(value, delimiter: ',')
          if value.is_a?(Array)
            value.flatten.compact.flat_map do |entry|
              entry.is_a?(String) ? split_delimited_string(entry, delimiter) : entry
            end
          elsif value.is_a?(String)
            split_delimited_string(value, delimiter)
          elsif value.nil?
            []
          else
            [value]
          end
        end

        # Converts a value into an array. Strings can be treated as
        # delimiter-defined lists.
        def self.arrayify(value, split_commas: false, split_delimiter: nil)
          delimiter = split_delimiter
          delimiter = ',' if delimiter.nil? && split_commas

          if value.nil?
            []
          elsif value.is_a?(Array)
            value.flatten.compact
          elsif !delimiter.nil? && value.is_a?(String)
            split_delimited_string(value, delimiter)
          else
            [value]
          end
        end

        # Normalises hash keys recursively to strings.
        def self.stringify_keys(value)
          return value unless value.is_a?(Hash)

          value.each_with_object({}) do |(key, child), copy|
            copy[key.to_s] = child.is_a?(Hash) ? stringify_keys(child) : child
          end
        end

        # Returns a hash from any input object, or an empty hash for unsupported values.
        def self.safe_hash(value)
          value.is_a?(Hash) ? stringify_keys(value) : {}
        end

        # Backwards-compatible alias for comma-delimited list parsing.
        def self.comma_delimited_array(value)
          delimited_array(value, delimiter: ',').map { |entry| entry.to_s.strip }.reject(&:empty?)
        end

        # Expands `layout` + `layouts` config into a unique array of layout names.
        def self.normalise_layouts(config, split_delimiter: ',')
          source = safe_hash(config)
          layouts = []
          layouts.concat(arrayify(source['layouts'], split_delimiter: split_delimiter)) if source.key?('layouts')
          layouts.concat(arrayify(source['layout'], split_delimiter: split_delimiter)) if source.key?('layout')
          layouts.map { |entry| entry.to_s.strip }.reject(&:empty?).uniq
        end
      end
    end
  end
end
