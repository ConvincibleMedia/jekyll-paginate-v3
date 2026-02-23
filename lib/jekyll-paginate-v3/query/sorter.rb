# frozen_string_literal: true

module Jekyll
  module Plugins
    module PaginateV3
      module Query
        # Multi-level sorter for v3 `sort` definitions.
        #
        # Example definitions:
        # - `sort: date desc`
        # - `sort: owner.name, date desc empty:first` (delimiter is configurable)
        # - `sort: ["featured desc", "date desc"]`
        #
        # Used by Pagination::Model to apply deterministic item ordering.
        class Sorter
          # Applies parsed sort instructions while preserving input order as a
          # final deterministic tiebreak.
          def self.apply(items, raw_sort, nested_separator:, equivalents:, split_delimiter: ',')
            instructions = parse(raw_sort, split_delimiter: split_delimiter)
            return items if instructions.empty?

            equivalent_lookup = Utils.build_equivalent_lookup(equivalents)

            # Keep original index as final tiebreak so ordering remains predictable.
            indexed_items = items.each_with_index.to_a
            indexed_items.sort! do |(left_item, left_index), (right_item, right_index)|
              comparison = compare_items(left_item, right_item, instructions, nested_separator, equivalent_lookup)
              comparison.zero? ? left_index <=> right_index : comparison
            end

            indexed_items.map(&:first)
          end

          # Parses `sort` config entries into normalised field instructions.
          def self.parse(raw_sort, split_delimiter: ',')
            entries = Utils.arrayify(raw_sort, split_delimiter: split_delimiter).map { |entry| entry.to_s.strip }.reject(&:empty?)

            entries.map do |entry|
              fragments = entry.split(/\s+/)
              field = fragments.shift.to_s.strip
              next nil if field.empty?

              direction = 'asc'
              empty = 'last'

              fragments.each do |fragment|
                token = fragment.to_s.strip.downcase
                case token
                when 'asc', 'ascending'
                  direction = 'asc'
                when 'desc', 'descending'
                  direction = 'desc'
                else
                  if token.start_with?('empty:')
                    empty_value = token.split(':', 2).last
                    empty = %w[first last].include?(empty_value) ? empty_value : empty
                  end
                end
              end

              {
                'field' => field,
                'direction' => direction,
                'empty' => empty
              }
            end.compact
          end

          class << self
            private

            def compare_items(left_item, right_item, instructions, nested_separator, equivalent_lookup)
              instructions.each do |instruction|
                comparison = compare_field(left_item, right_item, instruction, nested_separator, equivalent_lookup)
                return comparison unless comparison.zero?
              end

              0
            end

            def compare_field(left_item, right_item, instruction, nested_separator, equivalent_lookup)
              left_value = first_field_value(left_item, instruction['field'], nested_separator, equivalent_lookup)
              right_value = first_field_value(right_item, instruction['field'], nested_separator, equivalent_lookup)

              left_empty = empty_value?(left_value)
              right_empty = empty_value?(right_value)

              if left_empty || right_empty
                return 0 if left_empty && right_empty

                if instruction['empty'] == 'first'
                  return left_empty ? -1 : 1
                end

                return left_empty ? 1 : -1
              end

              rank_comparison = value_rank(left_value) <=> value_rank(right_value)
              return direction_adjust(rank_comparison, instruction['direction']) unless rank_comparison.zero?

              value_comparison = compare_ranked_values(left_value, right_value)
              direction_adjust(value_comparison, instruction['direction'])
            end

            def first_field_value(item, field, nested_separator, equivalent_lookup)
              data = item.respond_to?(:data) && item.data.is_a?(Hash) ? item.data.dup : {}

              collection_label = Utils.item_collection_label(item)
              data['collection'] = collection_label unless collection_label.nil?

              values = Utils.fetch_nested_values(data, field, nested_separator, equivalent_lookup)
              values.first
            end

            def empty_value?(value)
              value.nil? || (value.respond_to?(:empty?) && value.empty?)
            end

            def value_rank(value)
              return 0 if value == true
              return 1 if value == false
              return 2 if value.is_a?(Numeric)

              3
            end

            def compare_ranked_values(left, right)
              rank = value_rank(left)

              case rank
              when 0, 1
                0
              when 2
                left.to_f <=> right.to_f
              else
                left.to_s.downcase <=> right.to_s.downcase
              end
            end

            def direction_adjust(comparison, direction)
              direction == 'desc' ? -comparison : comparison
            end
          end
        end
      end
    end
  end
end
