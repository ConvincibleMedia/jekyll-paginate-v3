# frozen_string_literal: true

module Jekyll
  module Plugins
    module PaginateV3
      module Query
        class Filter
          private

          # Extracts candidate values from item frontmatter for one filter key.
          # Includes synthetic `collection` for parity with query/sort behaviour.
          def extract_item_values(item, key)
            data = item.respond_to?(:data) && item.data.is_a?(Hash) ? item.data : {}
            decorated_data = data.dup

            collection_label = Utils.item_collection_label(item)
            decorated_data['collection'] = collection_label unless collection_label.nil?

            fetch_raw_item_values(decorated_data, key)
          end

          # Evaluates one normalised filter definition node.
          def check_filter_definition(definition, item_values)
            if group_definition?(definition)
              check_group_filter(definition, item_values)
            elsif scalar_definition?(definition)
              check_scalar_filter(definition, item_values)
            elsif range_definition?(definition)
              scalar_candidates_from_item_values(item_values).any? { |value| range_match?(value, definition['min'], definition['max'], definition['mode']) }
            else
              false
            end
          end

          # Evaluates include/exclude group logic.
          def check_group_filter(group_definition, item_values)
            join_mode = group_definition['join'] || 'or'

            include_results = group_definition['include'].map { |entry| check_filter_definition(entry, item_values) }
            include_pass = include_results.empty? ? true : combine_join_results(include_results, join_mode)

            exclude_results = group_definition['exclude'].map { |entry| check_filter_definition(entry, item_values) }
            exclude_match = exclude_results.empty? ? false : combine_join_results(exclude_results, join_mode)

            include_pass && !exclude_match
          end

          # Combines boolean results under one join mode.
          def combine_join_results(results, join_mode)
            join_mode == 'and' ? results.all? : results.any?
          end

          # Reads terminal key values while preserving array values as arrays.
          # This allows scalar hash match modes to differentiate strict equality
          # from array includes behaviour.
          def fetch_raw_item_values(data, key)
            return [] unless data.is_a?(Hash)

            segments = Utils.split_nested_key(key, @nested_separator)
            return [] if segments.empty?

            nodes = [data]
            segments.each_with_index do |_, segment_index|
              next_nodes = []
              requested_key_path = segments.first(segment_index + 1).join(@nested_separator.to_s)

              nodes.each do |node|
                if node.is_a?(Array)
                  next_nodes.concat(node)
                  next
                end
                next unless node.is_a?(Hash)

                resolved_key = Utils.resolve_hash_key(node, requested_key_path, @equivalent_lookup, separator: @nested_separator)
                next if resolved_key.nil?

                next_nodes << Utils.read_hash(node, resolved_key)
              end

              nodes = if segment_index == segments.length - 1
                        next_nodes.compact
                      else
                        next_nodes.flatten(1).compact
                      end
              break if nodes.empty?
            end

            nodes.reject { |value| value.nil? || (value.respond_to?(:empty?) && value.empty?) }
          end

          # Flattens extracted values to scalars for non-scalar-specific checks.
          # No automatic string splitting is applied.
          def scalar_candidates_from_item_values(item_values)
            item_values.flat_map { |value| Utils.scalar_values(value) }.reject { |value| value.nil? || (value.respond_to?(:empty?) && value.empty?) }
          end

          # Evaluates scalar comparison rules against item values.
          # - strict: `==` only
          # - auto: `==` and includes on arrays
          # - only: includes only for single-item arrays
          # - first: compares only against the first N array entries
          def check_scalar_filter(filter_definition, item_values)
            match_value = filter_definition['match']
            match_mode = filter_definition['mode'] || 'auto'
            split_definition = filter_definition['split']
            first_count = filter_definition['first']

            item_values.any? do |item_value|
              comparable_value = apply_scalar_split(item_value, split_definition)
              scalar_value_matches?(comparable_value, match_value, match_mode, first_count)
            end
          end

          # Applies configured scalar split behaviour to one item value.
          def apply_scalar_split(value, split_definition)
            return value if split_definition == false

            delimiter = split_definition.is_a?(String) ? split_definition : @split_delimiter
            split_scalar_value(value, delimiter)
          end

          # Splits scalar/array values by delimiter and returns a compact array.
          def split_scalar_value(value, delimiter)
            if value.is_a?(Array)
              value.flat_map { |entry| split_scalar_value(entry, delimiter) }
            elsif value.is_a?(String)
              Utils.split_delimited_string(value, delimiter)
            elsif value.nil? || (value.respond_to?(:empty?) && value.empty?)
              []
            else
              [value]
            end
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

          # Emits a warning message through the optional logger callback.
          def log_warning(message)
            return if @log_lambda.nil?

            @log_lambda.call(message, 'warn')
          end
        end
      end
    end
  end
end
