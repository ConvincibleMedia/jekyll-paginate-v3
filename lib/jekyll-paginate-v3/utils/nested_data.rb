# frozen_string_literal: true

module Jekyll
  module Plugins
    module PaginateV3
      module Utils
        # Nested frontmatter lookup helpers with equivalent-key support.
        #
        # Used by filtering, sorting, and index grouping for nested key reads.

        # Splits a nested key according to configured separator.
        def self.split_nested_key(key, separator)
          key.to_s.split(separator.to_s).map(&:strip).reject(&:empty?)
        end

        # Builds lookup table used for equivalent key resolution.
        # Each entry is keyed by full key-path string (for example
        # `product.tag`), which allows equivalent mappings to be scoped to one
        # nested level only.
        def self.build_equivalent_lookup(raw_equivalents, split_delimiter: ',')
          return {} if raw_equivalents == false || raw_equivalents.nil?

          lookup = {}
          groups = raw_equivalents.is_a?(Array) ? raw_equivalents : [raw_equivalents]

          groups.each do |group|
            keys = if group.is_a?(Array)
                     group.flat_map { |entry| delimited_array(entry, delimiter: split_delimiter) }
                   else
                     delimited_array(group, delimiter: split_delimiter)
                   end
            keys = keys.map { |entry| entry.to_s.strip }.reject(&:empty?).uniq
            next if keys.length < 2

            keys.each { |key| lookup[key] = keys }
          end
          lookup
        end

        # Resolves the effective hash key for one requested nested key path.
        # Equivalent lookups are performed using the full requested path; only
        # terminal segments from that matched group are candidates for hash
        # access at this level.
        def self.resolve_hash_key(hash, requested_key_path, equivalent_lookup, separator: '.')
          string_key_path = requested_key_path.to_s.strip
          return nil if string_key_path.empty?

          group = equivalent_lookup[string_key_path] || [string_key_path]
          candidate_segments = group.map { |candidate_path| split_nested_key(candidate_path, separator).last }.reject(&:empty?).uniq

          candidate_segments.reverse_each do |candidate|
            return candidate if hash.key?(candidate)
            symbol_candidate = candidate.to_sym
            return symbol_candidate if hash.key?(symbol_candidate)
          end

          nil
        end

        # Reads a value from hash by either string or symbol key.
        def self.read_hash(hash, key)
          return hash[key] if hash.key?(key)

          string_key = key.to_s
          return hash[string_key] if hash.key?(string_key)

          symbol_key = string_key.to_sym
          return hash[symbol_key] if hash.key?(symbol_key)

          nil
        end

        # Retrieves all possible values from a nested key path.
        def self.fetch_nested_values(data, key_path, separator, equivalent_lookup)
          return [] unless data.is_a?(Hash)

          segments = split_nested_key(key_path, separator)
          return [] if segments.empty?

          nodes = [data]
          segments.each_with_index do |_, segment_index|
            next_nodes = []
            requested_key_path = segments.first(segment_index + 1).join(separator.to_s)

            nodes.each do |node|
              if node.is_a?(Array)
                next_nodes.concat(node)
                next
              end
              next unless node.is_a?(Hash)

              resolved_key = resolve_hash_key(node, requested_key_path, equivalent_lookup, separator: separator)
              next if resolved_key.nil?

              next_nodes << read_hash(node, resolved_key)
            end

            nodes = next_nodes.flatten(1).compact
            break if nodes.empty?
          end

          nodes.flatten.compact
        end

        # Converts a mixed scalar/array value into a flat array of scalar values.
        def self.scalar_values(value)
          if value.is_a?(Array)
            value.flatten.compact
          elsif value.nil?
            []
          else
            [value]
          end
        end
      end
    end
  end
end
