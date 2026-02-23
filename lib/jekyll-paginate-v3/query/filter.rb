# frozen_string_literal: true

require 'date'

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
          def self.filter_items(items, filters, nested_separator:, equivalents:, split_delimiter: ',', now_keyword: 'now', log_lambda: nil)
            engine = new(
              nested_separator: nested_separator,
              equivalents: equivalents,
              split_delimiter: split_delimiter,
              now_keyword: now_keyword,
              log_lambda: log_lambda
            )
            engine.filter_items(items, filters)
          end

          # Human-readable formatter used in logs/debug output.
          def self.filter_to_s(filter, split_delimiter: ',', now_keyword: 'now')
            formatter = new(
              nested_separator: '.',
              equivalents: [],
              split_delimiter: split_delimiter,
              now_keyword: now_keyword
            )

            normalised = formatter.send(:normalise_filter, filter)
            return '[invalid filter]' if normalised == false

            formatter.send(:filter_to_s_internal, normalised)
          end

          # Builds an engine configured for nested key and equivalent-key rules.
          def initialize(nested_separator:, equivalents:, split_delimiter:, now_keyword:, log_lambda: nil)
            @nested_separator = nested_separator
            @split_delimiter = Utils.normalise_split_delimiter(split_delimiter, ',')
            @now_keyword = now_keyword.to_s.strip
            @now_keyword = 'now' if @now_keyword.empty?
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

          private

          # Normalises any filter value to one recursive group definition.
          def normalise_filter(filter)
            normalised = normalise_filter_definition(filter)
            return false if normalised == false
            return normalised if group_definition?(normalised)

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
          # `first`, `firstN`).
          #
          # Returns:
          # - `[mode, embedded_first_count]`
          # - `false` when invalid.
          def normalise_scalar_match_mode(raw_mode)
            mode_value = raw_mode.to_s.strip.downcase
            mode_value = 'auto' if mode_value.empty?

            return [mode_value, nil] if %w[strict auto only].include?(mode_value)
            return ['first', nil] if %w[first firstn].include?(mode_value)

            first_count_match = mode_value.match(/\Afirst(\d+)\z/)
            return ['first', first_count_match[1].to_i] unless first_count_match.nil?

            false
          end

          # Normalises the `first` count used by `mode: first|firstN`.
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
            range_hash = hash_definition.select { |key, _| %w[min max].include?(key) }
            return false if range_hash.empty?

            %w[min max].each do |range_key|
              next unless range_hash.key?(range_key)

              parsed_value = interpret_numeric_or_date_keyword(range_hash[range_key])
              return false if parsed_value == false

              range_hash[range_key] = parsed_value
            end

            return false if range_hash['min'].nil? && range_hash['max'].nil?

            if !range_hash['min'].nil? && !range_hash['max'].nil?
              min_value = range_hash['min']
              max_value = range_hash['max']

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

            range_hash
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
          # `keywords.now` with optional +/- day offsets.
          #
          # Examples (assuming `keywords.now == "now"`):
          # - now
          # - now+1
          # - now - 0.5
          def interpret_numeric_or_date_keyword(value)
            if value.is_a?(String)
              now_expression = interpret_now_expression(value)
              return now_expression unless now_expression.nil?
            end

            interpret_numeric(value, must_cast: true)
          end

          # Parses configured now-keyword expressions into DateTime values.
          def interpret_now_expression(value)
            keyword_pattern = Regexp.escape(@now_keyword)
            expression = value.to_s.strip
            match = expression.match(/\A#{keyword_pattern}(?:\s*([+-])\s*(\d+(?:\.\d+)?))?\z/i)
            return nil if match.nil?

            offset_days = match[2].nil? ? 0.0 : match[2].to_f
            offset_days = -offset_days if match[1] == '-'

            DateTime.now + offset_days
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

          # Renders a normalised filter tree to readable text for diagnostics.
          def filter_to_s_internal(filter)
            join_mode = filter['join'] || 'or'

            include_fragments = filter['include'].map { |entry| filter_definition_to_s(entry) }
            include_text = include_fragments.empty? ? 'true' : include_fragments.join(" #{join_mode} ")

            exclude_fragments = filter['exclude'].map { |entry| filter_definition_to_s(entry) }
            return include_text if exclude_fragments.empty?

            exclude_text = exclude_fragments.join(" #{join_mode} ")
            "(#{include_text}) and not (#{exclude_text})"
          end

          # Renders one filter definition node.
          def filter_definition_to_s(definition)
            if group_definition?(definition)
              "(#{filter_to_s_internal(definition)})"
            elsif scalar_definition?(definition)
              split_text = definition['split'] == false ? 'split:false' : "split:'#{definition['split']}'"
              mode_text = definition['mode'] == 'first' ? "first:#{definition['first']}" : definition['mode']
              "match #{definition['match']} (#{mode_text}, #{split_text})"
            elsif range_definition?(definition)
              if definition.key?('min') && definition.key?('max')
                "#{definition['min']} to #{definition['max']}"
              elsif definition.key?('min')
                "#{definition['min']} or more"
              else
                "#{definition['max']} or less"
              end
            else
              '[invalid]'
            end
          end

          # Detects normalised group nodes.
          def group_definition?(definition)
            definition.is_a?(Hash) && definition.key?('include') && definition.key?('exclude') && definition.key?('join')
          end

          # Detects normalised scalar nodes.
          def scalar_definition?(definition)
            definition.is_a?(Hash) && definition.key?('match') && definition.key?('mode') && definition.key?('split')
          end

          # Detects normalised range nodes.
          def range_definition?(definition)
            definition.is_a?(Hash) && (definition.key?('min') || definition.key?('max'))
          end

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
              scalar_candidates_from_item_values(item_values).any? { |value| range_match?(value, definition['min'], definition['max']) }
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
          def range_match?(value, min_value, max_value)
            comparable_value = normalise_comparable_scalar(value)
            return false if comparable_value.nil?

            if !min_value.nil?
              return false unless values_comparable?(comparable_value, min_value)
              return false if comparable_value < min_value
            end

            if !max_value.nil?
              return false unless values_comparable?(comparable_value, max_value)
              return false if comparable_value > max_value
            end

            true
          rescue ArgumentError, NoMethodError
            false
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

