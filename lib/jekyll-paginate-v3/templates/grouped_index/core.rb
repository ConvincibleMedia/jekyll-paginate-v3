# frozen_string_literal: true

module Jekyll
  module Plugins
    module PaginateV3
      module Templates
        # Builds grouped generate-index entries for numeric, datetime, and
        # alphabetic range-based indexing.
        #
        # This class is used by Templates::Builder when a generate definition
        # includes `group`. It returns the same logical entry shape as ordinary
        # index grouping:
        #
        # - `filters`: filters to apply to generated template pagination config
        # - `values`: placeholder values by index key
        #
        # Grouped entries also include:
        #
        # - `token_values`: title/permalink token values by index key
        # - `group`: metadata used to build `paginator.group` payloads
        class GroupedIndex
          MINIMUM_GROW = 0.01
          MAXIMUM_GROW = 10_000.0
          MINIMUM_STEP = 0.001
          MAXIMUM_STEP = 100_000_000.0
          MAXIMUM_AUTOMATIC_GROUPS = 100
          MAXIMUM_TOTAL_GROUPS = 10_000
          MAXIMUM_ALPHABETIC_TOKEN_LENGTH = 3

          DURATION_UNITS = %w[day month year hour minute second].freeze
          CALENDAR_UNITS = %w[month year].freeze
          def initialize(key:, raw_group:, items:, nested_separator:, split_delimiter:, equivalents:, now_keyword:, today_keyword:, keywords: nil, log_lambda: nil)
            @key = key.to_s
            @raw_group = raw_group
            @items = items.is_a?(Array) ? items : []
            @nested_separator = nested_separator
            @split_delimiter = split_delimiter
            @equivalents = equivalents
            @equivalent_lookup = Utils.build_equivalent_lookup(equivalents)
            @now_keyword = normalise_keyword(now_keyword, 'now')
            @today_keyword = normalise_keyword(today_keyword, 'today')
            @keywords = Utils.safe_hash(keywords)
            @log_lambda = log_lambda

            @duration_keyword_by_unit = build_duration_keyword_map(@keywords)
            @duration_unit_by_keyword = @duration_keyword_by_unit.each_with_object({}) do |(unit, keyword), memo|
              memo[keyword] = unit
            end
          end

          # Expands grouped index configuration into generated template entries.
          def build_entries
            mode = resolve_grouping_mode
            prepared_candidates = prepare_candidates(@items)

            case mode
            when 'numeric'
              build_numeric_entries(prepared_candidates, normalise_numeric_group_config)
            when 'datetime'
              build_datetime_entries(prepared_candidates, normalise_datetime_group_config(prepared_candidates))
            when 'alphabetic'
              build_alphabetic_entries(prepared_candidates, normalise_alphabetic_group_config)
            else
              raise ArgumentError, "Unsupported group mode '#{mode}'."
            end
          end
        end
      end
    end
  end
end
