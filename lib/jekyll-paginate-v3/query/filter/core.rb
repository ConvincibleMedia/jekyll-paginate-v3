# frozen_string_literal: true

module Jekyll
  module Plugins
    module PaginateV3
      module Query
        # Filtering engine for pagination and generated index discovery.
        #
        # Public filter definitions are normalised into a single recursive group
        # shape:
        # - `{ include: [...], exclude: [...], join: and|or }`
        #
        # Shorthand forms (scalar, range, array, delimited string, scalar hash)
        # are all converted into this group model so evaluation follows one
        # consistent code path.
        class Filter
          # Class helper that instantiates a configured engine per call.
          def self.filter_items(items, filters, nested_separator:, equivalents:, split_delimiter: ',', now_keyword: 'now', today_keyword: 'today', log_lambda: nil)
            engine = new(
              nested_separator: nested_separator,
              equivalents: equivalents,
              split_delimiter: split_delimiter,
              now_keyword: now_keyword,
              today_keyword: today_keyword,
              log_lambda: log_lambda
            )
            engine.filter_items(items, filters)
          end

          # Human-readable formatter used in logs/debug output.
          def self.filter_to_s(filter, split_delimiter: ',', now_keyword: 'now', today_keyword: 'today')
            formatter = new(
              nested_separator: '.',
              equivalents: [],
              split_delimiter: split_delimiter,
              now_keyword: now_keyword,
              today_keyword: today_keyword
            )

            normalised = formatter.send(:normalise_filter, filter)
            return '[invalid filter]' if normalised == false

            formatter.send(:filter_to_s_internal, normalised)
          end

          # Builds an engine configured for nested key and equivalent-key rules.
          def initialize(nested_separator:, equivalents:, split_delimiter:, now_keyword:, today_keyword:, log_lambda: nil)
            @nested_separator = nested_separator
            @split_delimiter = Utils.normalise_split_delimiter(split_delimiter, ',')
            @now_keyword = now_keyword.to_s.strip
            @now_keyword = 'now' if @now_keyword.empty?
            @today_keyword = today_keyword.to_s.strip
            @today_keyword = 'today' if @today_keyword.empty?
            @equivalent_lookup = Utils.build_equivalent_lookup(equivalents)
            @log_lambda = log_lambda
          end

          # Applies all configured filters sequentially (logical AND across keys).
          def filter_items(items, filters)
            return items unless filters.is_a?(Hash)

            current_items = items
            Utils.safe_hash(filters).each do |raw_key, raw_filter|
              normalised = normalise_filter(raw_filter)
              next if normalised == false

              key = raw_key.to_s
              current_items = current_items.select do |item|
                values = extract_item_values(item, key)
                next false if values.empty?

                check_filter_definition(normalised, values)
              end
            end

            current_items
          end
        end
      end
    end
  end
end
