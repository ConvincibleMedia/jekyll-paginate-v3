# frozen_string_literal: true

require 'date'
require 'unicode_normalize'

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

          # Creates one grouped-index evaluator for a single frontmatter key.
          #
          # `items` should already reflect any generate-level filters so
          # grouping is only calculated from the relevant source set.
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

          private

          # Normalises configured special keywords while preserving custom names.
          def normalise_keyword(raw_keyword, fallback)
            keyword = raw_keyword.to_s.strip
            keyword.empty? ? fallback : keyword
          end

          # Builds configured keyword mapping for duration units used by
          # datetime grouped indexing.
          def build_duration_keyword_map(raw_keywords)
            keywords = Utils.safe_hash(raw_keywords)

            DURATION_UNITS.each_with_object({}) do |unit, memo|
              memo[unit] = normalise_keyword(keywords[unit], unit).downcase
            end
          end

          # Returns regex alternation for configured duration keywords.
          def duration_keywords_pattern
            @duration_keywords_pattern ||= @duration_keyword_by_unit.values.map { |keyword| Regexp.escape(keyword) }.join('|')
          end

          # Resolves one configured duration keyword back to canonical unit name.
          def canonical_duration_unit(keyword)
            @duration_unit_by_keyword[keyword.to_s.strip.downcase]
          end

          # Chooses grouping mode using config-first hints and then candidate
          # value sampling when config alone is ambiguous.
          def resolve_grouping_mode
            hinted_mode = explicit_mode_hint
            return hinted_mode unless hinted_mode.nil?

            inferred_mode = inferred_mode_from_item_values
            return inferred_mode unless inferred_mode.nil?

            'numeric'
          end

          # Attempts to detect an explicit grouping mode directly from `group`.
          def explicit_mode_hint
            case @raw_group
            when Hash
              hash_group = Utils.safe_hash(@raw_group)
              start_value = hash_group['start']
              return 'alphabetic' if alphabetic_start_token?(start_value)
              return 'alphabetic' if hash_group.key?('other')
              return 'datetime' if datetime_group_hash_hint?(hash_group)
            when String
              value = @raw_group.strip
              return nil if value.empty?
              return 'datetime' if duration_token?(value) || datetime_anchor_token?(value) || datetime_keyword_expression?(value)
              return 'numeric' if numeric_string?(value)
              return 'alphabetic' if alphabetic_start_token?(value)
            when Integer, Float
              return nil
            end

            nil
          end

          # Determines whether a hash-group config appears datetime-oriented.
          def datetime_group_hash_hint?(hash_group)
            %w[start step min max].any? do |key|
              value = hash_group[key]
              next false if value.nil?

              datetime_hint_value?(value)
            end
          end

          # Detects whether one config value strongly hints datetime mode.
          def datetime_hint_value?(value)
            if value.is_a?(Array)
              return value.any? { |entry| datetime_hint_value?(entry) }
            end

            if value.is_a?(String)
              stripped = value.strip
              return false if stripped.empty?
              return true if duration_token?(stripped)
              return true if datetime_anchor_token?(stripped)
              return true if datetime_keyword_expression?(stripped)
              return false if numeric_string?(stripped)
              return !interpret_datetime_value(stripped).nil?
            end

            value.is_a?(Date) || value.is_a?(DateTime) || value.is_a?(Time)
          end

          # Uses extracted item values to infer grouping mode when not explicit.
          def inferred_mode_from_item_values
            counts = {
              'numeric' => 0,
              'datetime' => 0,
              'alphabetic' => 0
            }

            prepare_candidates(@items).each do |candidate|
              counts['numeric'] += 1 unless candidate['numeric'].nil?
              counts['datetime'] += 1 unless candidate['datetime'].nil?
              counts['alphabetic'] += 1 if candidate['alpha_starts_with_letter']
            end

            highest_count = counts.values.max
            return nil if highest_count.nil? || highest_count.zero?

            preferred_order = %w[numeric datetime alphabetic]
            preferred_order.each do |mode|
              return mode if counts[mode] == highest_count
            end

            nil
          end

          # Extracts parse-ready candidates for numeric, datetime, and
          # alphabetic interpretation per item. Each item contributes at most one
          # effective value in any specific mode.
          def prepare_candidates(items)
            items.map do |item|
              raw_values = raw_values_for_key(item)

              numeric_value = nil
              datetime_value = nil
              alpha_value = nil
              alpha_starts_with_letter = false

              raw_values.each do |raw_value|
                numeric_value = interpret_numeric_value(raw_value) if numeric_value.nil?
                datetime_value = interpret_datetime_value(raw_value) if datetime_value.nil?

                if alpha_value.nil?
                  alpha_candidate = normalise_alpha_value(raw_value)
                  alpha_value = alpha_candidate['letters']
                  alpha_starts_with_letter = alpha_candidate['starts_with_letter']
                end

                break unless numeric_value.nil? || datetime_value.nil? || alpha_value.nil?
              end

              {
                'item' => item,
                'raw_values' => raw_values,
                'numeric' => numeric_value,
                'datetime' => datetime_value,
                'alpha' => alpha_value,
                'alpha_starts_with_letter' => alpha_starts_with_letter
              }
            end
          end

          # Reads scalar values for one key from frontmatter, including nested
          # and equivalent-key resolution. String values are split by configured
          # delimiter to mirror other query semantics.
          def raw_values_for_key(item)
            data = item.respond_to?(:data) && item.data.is_a?(Hash) ? item.data.dup : {}
            collection_label = Utils.item_collection_label(item)
            data['collection'] = collection_label unless collection_label.nil?

            values = Utils.fetch_nested_values(data, @key, @nested_separator, @equivalent_lookup)
            values.flat_map do |value|
              if value.is_a?(String)
                split_values = Utils.split_delimited_string(value, @split_delimiter)
                split_values.empty? ? [value] : split_values
              else
                Utils.scalar_values(value)
              end
            end.reject do |value|
              value.nil? || (value.respond_to?(:empty?) && value.empty?)
            end
          end

          # Parses numeric candidates using the same integer/float rules as
          # filter range parsing.
          def interpret_numeric_value(value)
            return value.to_f if value.is_a?(Integer) || value.is_a?(Float)

            return nil unless value.is_a?(String)

            stripped = value.strip
            return nil if stripped.empty?
            return stripped.to_i.to_f if stripped.match?(/\A[+-]?\d+\z/)
            return stripped.to_f if stripped.match?(/\A[+-]?\d+\.\d+\z/)

            nil
          end

          # Parses datetime candidates from Date/Time values or parseable
          # datetime strings.
          def interpret_datetime_value(value)
            return value.to_datetime if value.is_a?(DateTime)
            return value.to_datetime if value.is_a?(Time)
            return value.to_datetime if value.is_a?(Date)

            return nil unless value.is_a?(String)

            stripped = value.strip
            return nil if stripped.empty?

            DateTime.parse(stripped)
          rescue ArgumentError
            nil
          end

          # Normalises one value for alphabetic comparison:
          # - stringified
          # - downcased
          # - best-effort transliteration to ASCII
          # - letters-only token for grouping
          def normalise_alpha_value(value)
            string_value = value.to_s
            transliterated = string_value.unicode_normalize(:nfkd).encode('ASCII', invalid: :replace, undef: :replace, replace: '').downcase
            starts_with_letter = transliterated.match?(/\A[a-z]/)
            letters = transliterated.gsub(/[^a-z]/, '')

            {
              'letters' => letters,
              'starts_with_letter' => starts_with_letter
            }
          rescue StandardError
            {
              'letters' => '',
              'starts_with_letter' => false
            }
          end

          # Detects whether a value can be used as an alphabetic start token.
          def alphabetic_start_token?(value)
            return false unless value.is_a?(String)

            token = normalise_alpha_value(value)['letters']
            !token.empty?
          end

          # Detects duration-like expressions such as `month(2)`.
          def duration_token?(value)
            return false unless value.is_a?(String)

            value.strip.match?(/\A(?:#{duration_keywords_pattern})(?:\s*\(.*\))?\z/i)
          end

          # Detects anchor expressions such as `month(today)` or `hour(now)`.
          def datetime_anchor_token?(value)
            return false unless value.is_a?(String)

            stripped = value.strip
            match = stripped.match(/\A(#{duration_keywords_pattern})\s*\((.+)\)\z/i)
            return false if match.nil?

            inner = match[2].to_s.strip
            datetime_keyword_expression?(inner)
          end

          # Detects `now` / `today` keyword expressions with optional offsets.
          def datetime_keyword_expression?(value)
            return false unless value.is_a?(String)

            stripped = value.strip
            keyword_patterns = [Regexp.escape(@now_keyword), Regexp.escape(@today_keyword)]
            stripped.match?(/\A(?:#{keyword_patterns.join('|')})(?:\s*[+-]\s*\d+)?\z/i)
          end

          # Detects integer/float string forms.
          def numeric_string?(value)
            value.to_s.strip.match?(/\A[+-]?\d+(?:\.\d+)?\z/)
          end

          # Parses and validates numeric grouping configuration.
          def normalise_numeric_group_config
            if @raw_group.is_a?(Integer) || @raw_group.is_a?(Float) || (@raw_group.is_a?(String) && numeric_string?(@raw_group))
              step_value = parse_positive_numeric(@raw_group, name: 'group')
              return {
                'start' => 0.0,
                'step_pattern' => [step_value],
                'grow' => 1.0,
                'min_step' => nil,
                'max_step' => nil,
                'empty' => false,
                'total' => nil
              }
            end

            hash_group = Utils.safe_hash(@raw_group)
            if hash_group.empty?
              raise ArgumentError, '`group` must be numeric, string, or hash for grouped numeric indexing.'
            end

            allowed_keys = %w[start step grow min max empty total]
            validate_allowed_keys!(hash_group, allowed_keys, context: 'numeric')

            unless hash_group.key?('step')
              raise ArgumentError, '`group.step` is required for numeric grouped indexing.'
            end

            step_pattern = parse_numeric_step_pattern(hash_group['step'])
            if step_pattern.length > 1 && hash_group.key?('grow')
              raise ArgumentError, '`group.step` arrays cannot be used together with `group.grow`.'
            end

            grow_factor = if hash_group.key?('grow')
                            parse_grow_factor(hash_group['grow'])
                          else
                            1.0
                          end

            {
              'start' => hash_group.key?('start') ? parse_numeric(hash_group['start'], name: 'group.start') : 0.0,
              'step_pattern' => step_pattern,
              'grow' => grow_factor,
              'min_step' => hash_group.key?('min') ? parse_positive_numeric(hash_group['min'], name: 'group.min') : nil,
              'max_step' => hash_group.key?('max') ? parse_positive_numeric(hash_group['max'], name: 'group.max') : nil,
              'empty' => parse_boolean(hash_group['empty']),
              'total' => hash_group.key?('total') ? parse_total_group_count(hash_group['total']) : nil
            }
          end

          # Parses and validates datetime grouping configuration.
          def normalise_datetime_group_config(candidates)
            raw_group_hash = if @raw_group.is_a?(Hash)
                               Utils.safe_hash(@raw_group)
                             else
                               {
                                 'step' => @raw_group
                               }
                             end

            allowed_keys = %w[start step grow min max empty total]
            validate_allowed_keys!(raw_group_hash, allowed_keys, context: 'datetime')

            unless raw_group_hash.key?('step')
              raise ArgumentError, '`group.step` is required for datetime grouped indexing.'
            end

            step_pattern = parse_datetime_step_pattern(raw_group_hash['step'])
            if step_pattern.length > 1 && raw_group_hash.key?('grow')
              raise ArgumentError, '`group.step` arrays cannot be used together with `group.grow`.'
            end

            grow_factor = if raw_group_hash.key?('grow')
                            parse_grow_factor(raw_group_hash['grow'])
                          else
                            1.0
                          end

            inferred_start = infer_default_datetime_start(candidates, step_pattern.first)
            configured_start = raw_group_hash.key?('start') ? parse_datetime_start(raw_group_hash['start']) : inferred_start

            {
              'start' => configured_start,
              'step_pattern' => step_pattern,
              'grow' => grow_factor,
              'min_step' => raw_group_hash.key?('min') ? parse_datetime_duration(raw_group_hash['min'], name: 'group.min') : nil,
              'max_step' => raw_group_hash.key?('max') ? parse_datetime_duration(raw_group_hash['max'], name: 'group.max') : nil,
              'empty' => parse_boolean(raw_group_hash['empty']),
              'total' => raw_group_hash.key?('total') ? parse_total_group_count(raw_group_hash['total']) : nil,
              'time_precision' => datetime_time_precision?(raw_group_hash, step_pattern)
            }
          end

          # Parses and validates alphabetic grouping configuration.
          def normalise_alphabetic_group_config
            if @raw_group.is_a?(String)
              return {
                'start' => normalise_alphabetic_start(@raw_group),
                'step' => 1,
                'empty' => false,
                'other' => nil
              }
            end

            hash_group = Utils.safe_hash(@raw_group)
            if hash_group.empty?
              raise ArgumentError, '`group` must be a string or hash for alphabetic grouped indexing.'
            end

            allowed_keys = %w[start step empty other]
            validate_allowed_keys!(hash_group, allowed_keys, context: 'alphabetic')

            unless hash_group.key?('step')
              raise ArgumentError, '`group.step` is required for alphabetic grouped indexing.'
            end

            step_value = parse_positive_integer(hash_group['step'], name: 'group.step')
            if step_value > MAXIMUM_STEP.to_i
              raise ArgumentError, '`group.step` is too large for alphabetic grouped indexing.'
            end

            {
              'start' => normalise_alphabetic_start(hash_group.key?('start') ? hash_group['start'] : 'a'),
              'step' => step_value,
              'empty' => parse_boolean(hash_group['empty']),
              'other' => hash_group.key?('other') ? hash_group['other'].to_s : nil
            }
          end

          # Validates that no unsupported keys are present in grouped config.
          def validate_allowed_keys!(hash_group, allowed_keys, context:)
            invalid_keys = hash_group.keys - allowed_keys
            return if invalid_keys.empty?

            raise ArgumentError, "Invalid keys for #{context} grouped indexing: #{invalid_keys.join(', ')}."
          end

          # Parses numeric step definitions.
          def parse_numeric_step_pattern(raw_step)
            if raw_step.is_a?(Array)
              pattern = raw_step.flatten.compact.map { |entry| parse_positive_numeric(entry, name: 'group.step[]') }
              raise ArgumentError, '`group.step` array must include at least one positive value.' if pattern.empty?

              return pattern
            end

            [parse_positive_numeric(raw_step, name: 'group.step')]
          end

          # Parses datetime step definitions.
          def parse_datetime_step_pattern(raw_step)
            if raw_step.is_a?(Array)
              pattern = raw_step.flatten.compact.map { |entry| parse_datetime_duration(entry, name: 'group.step[]') }
              raise ArgumentError, '`group.step` array must include at least one positive duration.' if pattern.empty?

              return pattern
            end

            [parse_datetime_duration(raw_step, name: 'group.step')]
          end

          # Parses one grow factor and validates supported bounds.
          def parse_grow_factor(raw_grow)
            grow_value = parse_positive_numeric(raw_grow, name: 'group.grow')
            if grow_value < MINIMUM_GROW || grow_value > MAXIMUM_GROW
              raise ArgumentError, "`group.grow` must be between #{MINIMUM_GROW} and #{MAXIMUM_GROW}."
            end

            grow_value
          end

          # Parses one configured total group count.
          def parse_total_group_count(raw_total)
            total = parse_positive_integer(raw_total, name: 'group.total')
            if total < 1 || total > MAXIMUM_TOTAL_GROUPS
              raise ArgumentError, "`group.total` must be within 1..#{MAXIMUM_TOTAL_GROUPS}."
            end

            total
          end

          # Parses any numeric scalar; raises for non-numeric values.
          def parse_numeric(raw_value, name:)
            numeric_value = interpret_numeric_value(raw_value)
            if numeric_value.nil?
              raise ArgumentError, "`#{name}` must be numeric."
            end

            numeric_value.to_f
          end

          # Parses strictly positive numeric values.
          def parse_positive_numeric(raw_value, name:)
            numeric_value = parse_numeric(raw_value, name: name)
            if numeric_value <= 0.0
              raise ArgumentError, "`#{name}` must be greater than zero."
            end

            numeric_value
          end

          # Parses strictly positive integers.
          def parse_positive_integer(raw_value, name:)
            integer_value = parse_numeric(raw_value, name: name).to_i
            if integer_value <= 0
              raise ArgumentError, "`#{name}` must be a positive integer."
            end

            integer_value
          end

          # Parses loose boolean values.
          def parse_boolean(raw_value)
            return raw_value if raw_value == true || raw_value == false

            raw_value.to_s.strip.casecmp('true').zero?
          end

          # Parses datetime start values including:
          # - absolute datetimes
          # - `now` / `today` expressions with optional integer offsets
          # - anchored expressions such as `year(today)`, `month(now)`
          def parse_datetime_start(raw_value)
            return raw_value.to_datetime if raw_value.is_a?(DateTime)
            return raw_value.to_datetime if raw_value.is_a?(Time)
            return raw_value.to_datetime if raw_value.is_a?(Date)

            if raw_value.is_a?(Integer) || raw_value.is_a?(Float)
              return DateTime.new(1970, 1, 1, 0, 0, 0) + Rational((raw_value.to_f * 86_400).round, 86_400)
            end

            unless raw_value.is_a?(String)
              raise ArgumentError, '`group.start` for datetime grouping must be date-like, keyword-like, or numeric.'
            end

            stripped = raw_value.strip
            raise ArgumentError, '`group.start` for datetime grouping cannot be blank.' if stripped.empty?

            anchored = interpret_datetime_anchor_expression(stripped)
            return anchored unless anchored.nil?

            keyword_value = interpret_datetime_keyword_expression(stripped, range_key: 'min')
            return keyword_value unless keyword_value.nil?

            DateTime.parse(stripped)
          rescue ArgumentError
            raise ArgumentError, "`group.start` could not be parsed as datetime: #{raw_value.inspect}."
          end

          # Parses datetime duration definitions used by `step`, `min`, and
          # `max` in datetime grouped indexing.
          #
          # Supported forms:
          # - Numeric (days)
          # - `day(x)`, `month(x)`, `year(x)`, `hour(x)`, `minute(x)`, `second(x)`
          def parse_datetime_duration(raw_value, name:)
            if raw_value.is_a?(Integer) || raw_value.is_a?(Float)
              amount = raw_value.to_f
              raise ArgumentError, "`#{name}` must be greater than zero." if amount <= 0.0

              return {
                'unit' => 'day',
                'amount' => amount
              }
            end

            unless raw_value.is_a?(String)
              raise ArgumentError, "`#{name}` must be numeric or a duration token."
            end

            stripped = raw_value.strip
            raise ArgumentError, "`#{name}` cannot be blank." if stripped.empty?

            if numeric_string?(stripped)
              amount = stripped.to_f
              raise ArgumentError, "`#{name}` must be greater than zero." if amount <= 0.0

              return {
                'unit' => 'day',
                'amount' => amount
              }
            end

            bare_unit = canonical_duration_unit(stripped)
            unless bare_unit.nil?
              return {
                'unit' => bare_unit,
                'amount' => 1.0
              }
            end

            match = stripped.match(/\A(#{duration_keywords_pattern})\s*\((.+)\)\z/i)
            if match.nil?
              raise ArgumentError, "`#{name}` must be numeric or one of: #{@duration_keyword_by_unit.values.join(', ')}(x)."
            end

            unit = canonical_duration_unit(match[1])
            amount_text = match[2].to_s.strip
            amount = parse_numeric(amount_text, name: name)

            if amount <= 0.0
              raise ArgumentError, "`#{name}` must be greater than zero."
            end

            if CALENDAR_UNITS.include?(unit) && (amount % 1.0).positive?
              raise ArgumentError, "`#{name}` for unit #{unit} must be a whole number."
            end

            {
              'unit' => unit,
              'amount' => amount
            }
          end

          # Detects whether datetime permalink placeholders should include
          # clock-level precision.
          def datetime_time_precision?(raw_hash, step_pattern)
            return true if step_pattern.any? { |step| %w[hour minute second].include?(step['unit']) }
            return true if step_pattern.any? { |step| step['unit'] == 'day' && (step['amount'] % 1.0).positive? }
            return true if raw_hash.key?('start') && datetime_start_has_time_precision?(raw_hash['start'])

            %w[min max].any? do |key|
              next false unless raw_hash.key?(key)

              begin
                duration = parse_datetime_duration(raw_hash[key], name: "group.#{key}")
                %w[hour minute second].include?(duration['unit']) || (duration['unit'] == 'day' && (duration['amount'] % 1.0).positive?)
              rescue StandardError
                false
              end
            end
          end

          # Indicates whether a datetime `start` expression implies clock-level
          # precision in permalink placeholders.
          def datetime_start_has_time_precision?(raw_start)
            return true if raw_start.is_a?(Time)
            return true if raw_start.is_a?(DateTime) && (raw_start.hour.positive? || raw_start.min.positive? || raw_start.sec.positive?)

            return false unless raw_start.is_a?(String)

            stripped = raw_start.strip
            return false if stripped.empty?
            precise_units = [@duration_keyword_by_unit['hour'], @duration_keyword_by_unit['minute'], @duration_keyword_by_unit['second']].map { |keyword| Regexp.escape(keyword) }.join('|')
            return true if stripped.match?(/\A(?:#{precise_units})(?:\s*\(|\z)/i)
            return true if stripped.match?(/\A#{Regexp.escape(@now_keyword)}(?:\s*[+-]\s*\d+)?\z/i)

            parsed = DateTime.parse(stripped)
            parsed.hour.positive? || parsed.min.positive? || parsed.sec.positive?
          rescue ArgumentError
            false
          end

          # Builds grouped entries for numeric mode.
          def build_numeric_entries(candidates, config)
            candidate_items = candidates.map do |candidate|
              {
                'item' => candidate['item'],
                'value' => candidate['numeric']
              }
            end.select { |entry| !entry['value'].nil? }

            spans = build_numeric_spans(candidate_items, config)
            build_numeric_entries_from_spans(spans, candidate_items, config)
          end

          # Creates numeric span boundaries according to config, growth, and
          # safety limits.
          def build_numeric_spans(candidate_items, config)
            start_value = config['start'].to_f
            total_groups = config['total']
            step_pattern = config['step_pattern']
            grow_factor = config['grow']
            min_step = config['min_step']
            max_step = config['max_step']

            max_item_value = candidate_items.map { |entry| entry['value'].to_f }.max

            group_count = if total_groups.nil?
                            infer_automatic_numeric_group_count(start_value, max_item_value, step_pattern, grow_factor, min_step, max_step)
                          else
                            total_groups
                          end

            group_count = 1 if group_count <= 0 && config['empty']
            return [] if group_count <= 0

            spans = []
            current_start = start_value
            current_step = nil

            group_count.times do |index|
              current_step = numeric_step_for_group(index, current_step, step_pattern, grow_factor, min_step, max_step)
              calculated_end = current_start + current_step
              open_ended = !total_groups.nil? && index == group_count - 1

              spans << {
                'index' => index + 1,
                'start' => current_start,
                'end' => open_ended ? nil : calculated_end,
                'token_upper_bound' => calculated_end
              }

              current_start = calculated_end
            end

            spans
          end

          # Calculates how many numeric spans are needed when `total` is not
          # explicitly configured.
          def infer_automatic_numeric_group_count(start_value, max_item_value, step_pattern, grow_factor, min_step, max_step)
            return 0 if max_item_value.nil?
            return 0 if max_item_value < start_value

            groups = 0
            current_start = start_value.to_f
            current_step = nil

            while current_start < max_item_value
              groups += 1
              if groups > MAXIMUM_AUTOMATIC_GROUPS
                raise ArgumentError, "Grouped indexing implies more than #{MAXIMUM_AUTOMATIC_GROUPS} groups; set `group.total` to opt in explicitly."
              end

              current_step = numeric_step_for_group(groups - 1, current_step, step_pattern, grow_factor, min_step, max_step)
              current_start += current_step
            end

            [groups, 1].max
          end

          # Resolves step size for one numeric group index.
          def numeric_step_for_group(index, previous_step, step_pattern, grow_factor, min_step, max_step)
            base_step = step_pattern[[index, step_pattern.length - 1].min].to_f

            step = if index.zero?
                     base_step
                   elsif step_pattern.length > 1
                     base_step
                   else
                     previous_step.to_f * grow_factor
                   end

            step = clamp_numeric_step(step, min_step: min_step, max_step: max_step)
            raise ArgumentError, 'Numeric grouped indexing produced a non-positive step size.' if step <= 0.0

            step
          end

          # Applies configured and hard safety bounds to one numeric step.
          def clamp_numeric_step(step, min_step:, max_step:)
            lower_bound = min_step.nil? ? MINIMUM_STEP : [min_step.to_f, MINIMUM_STEP].max
            upper_bound = max_step.nil? ? MAXIMUM_STEP : [max_step.to_f, MAXIMUM_STEP].min

            [[step, lower_bound].max, upper_bound].min
          end

          # Builds concrete numeric grouped entries and attaches matching items.
          def build_numeric_entries_from_spans(spans, candidate_items, config)
            grouped_items = spans.each_with_object({}) { |span, memo| memo[span['index']] = [] }

            candidate_items.each do |entry|
              value = entry['value'].to_f
              span = spans.find do |candidate_span|
                range_value_within_span?(value, candidate_span['start'], candidate_span['end'], first_group: candidate_span['index'] == 1)
              end
              next if span.nil?

              grouped_items[span['index']] << entry['item']
            end

            entries = []
            spans.each do |span|
              items = grouped_items.fetch(span['index'])
              next if items.empty? && !config['empty']

              placeholder_value = format_numeric_token(span['token_upper_bound'])

              entry_filter = build_range_filter(
                min_value: span['start'],
                max_value: span['end'],
                min_inclusive: span['index'] == 1
              )

              entries << {
                'filters' => {
                  @key => entry_filter
                },
                'values' => {
                  @key => placeholder_value
                },
                'token_values' => {
                  @key => {
                    'title' => placeholder_value,
                    'permalink' => placeholder_value
                  }
                },
                'group' => {
                  'mode' => 'numeric',
                  'start' => format_numeric_token(span['start']),
                  'end' => span['end'].nil? ? nil : format_numeric_token(span['end']),
                  'order' => span['index'],
                  'range' => true,
                  'other' => false
                },
                'items' => items.uniq
              }
            end

            entries
          end

          # Builds grouped entries for datetime mode.
          def build_datetime_entries(candidates, config)
            candidate_items = candidates.map do |candidate|
              {
                'item' => candidate['item'],
                'value' => candidate['datetime']
              }
            end.select { |entry| !entry['value'].nil? }

            spans = build_datetime_spans(candidate_items, config)
            build_datetime_entries_from_spans(spans, candidate_items, config)
          end

          # Creates datetime span boundaries according to calendar-aware step
          # increments.
          def build_datetime_spans(candidate_items, config)
            start_value = config['start']
            total_groups = config['total']
            step_pattern = config['step_pattern']
            grow_factor = config['grow']
            min_step = config['min_step']
            max_step = config['max_step']

            max_item_value = candidate_items.map { |entry| entry['value'] }.max

            group_count = if total_groups.nil?
                            infer_automatic_datetime_group_count(start_value, max_item_value, step_pattern, grow_factor, min_step, max_step)
                          else
                            total_groups
                          end

            group_count = 1 if group_count <= 0 && config['empty']
            return [] if group_count <= 0

            spans = []
            current_start = start_value
            current_step = nil

            group_count.times do |index|
              current_step = datetime_step_for_group(index, current_step, step_pattern, grow_factor, min_step, max_step)
              calculated_end = add_datetime_duration(current_start, current_step)
              open_ended = !total_groups.nil? && index == group_count - 1

              spans << {
                'index' => index + 1,
                'start' => current_start,
                'end' => open_ended ? nil : calculated_end,
                'token_upper_bound' => calculated_end
              }

              current_start = calculated_end
            end

            spans
          end

          # Calculates how many datetime spans are needed when `total` is not
          # explicitly configured.
          def infer_automatic_datetime_group_count(start_value, max_item_value, step_pattern, grow_factor, min_step, max_step)
            return 0 if max_item_value.nil?
            return 0 if max_item_value < start_value

            groups = 0
            current_start = start_value
            current_step = nil

            while current_start < max_item_value
              groups += 1
              if groups > MAXIMUM_AUTOMATIC_GROUPS
                raise ArgumentError, "Grouped indexing implies more than #{MAXIMUM_AUTOMATIC_GROUPS} groups; set `group.total` to opt in explicitly."
              end

              current_step = datetime_step_for_group(groups - 1, current_step, step_pattern, grow_factor, min_step, max_step)
              current_start = add_datetime_duration(current_start, current_step)
            end

            [groups, 1].max
          end

          # Resolves step value for one datetime group index, applying growth
          # and configured/hard safety bounds.
          def datetime_step_for_group(index, previous_step, step_pattern, grow_factor, min_step, max_step)
            base_step = Utils.deep_copy(step_pattern[[index, step_pattern.length - 1].min])

            resolved_step = if index.zero?
                              base_step
                            elsif step_pattern.length > 1
                              base_step
                            else
                              grown = Utils.deep_copy(previous_step)
                              grown['amount'] = grown['amount'].to_f * grow_factor
                              grown
                            end

            resolved_step = clamp_datetime_step(resolved_step, min_step: min_step, max_step: max_step)
            if resolved_step['amount'].to_f <= 0.0
              raise ArgumentError, 'Datetime grouped indexing produced a non-positive step size.'
            end

            resolved_step
          end

          # Applies configured and hard safety bounds to one datetime step.
          def clamp_datetime_step(step, min_step:, max_step:)
            scalar = datetime_duration_to_scalar(step)

            min_scalar = if min_step.nil?
                           MINIMUM_STEP
                         else
                           [datetime_duration_to_scalar(min_step), MINIMUM_STEP].max
                         end
            max_scalar = if max_step.nil?
                           MAXIMUM_STEP
                         else
                           [datetime_duration_to_scalar(max_step), MAXIMUM_STEP].min
                         end

            clamped_scalar = [[scalar, min_scalar].max, max_scalar].min
            datetime_scalar_to_duration(clamped_scalar, template: step)
          end

          # Converts one datetime duration to a comparable scalar:
          # - calendar units as months
          # - fixed units as days
          def datetime_duration_to_scalar(duration)
            unit = duration['unit']
            amount = duration['amount'].to_f

            case unit
            when 'year'
              amount * 12.0
            when 'month'
              amount
            when 'day'
              amount
            when 'hour'
              amount / 24.0
            when 'minute'
              amount / 1_440.0
            when 'second'
              amount / 86_400.0
            else
              amount
            end
          end

          # Converts a clamped scalar back into the original duration unit.
          def datetime_scalar_to_duration(scalar_value, template:)
            unit = template['unit']
            case unit
            when 'year'
              amount = (scalar_value / 12.0).round
              amount = 1 if amount < 1
            when 'month'
              amount = scalar_value.round
              amount = 1 if amount < 1
            when 'day'
              amount = scalar_value.to_f
            when 'hour'
              amount = scalar_value.to_f * 24.0
            when 'minute'
              amount = scalar_value.to_f * 1_440.0
            when 'second'
              amount = scalar_value.to_f * 86_400.0
            else
              amount = scalar_value.to_f
            end

            {
              'unit' => unit,
              'amount' => amount
            }
          end

          # Adds one parsed duration to a DateTime using calendar-aware month
          # and year operations.
          def add_datetime_duration(datetime_value, duration)
            unit = duration['unit']
            amount = duration['amount']

            case unit
            when 'year'
              datetime_value >> (amount.to_i * 12)
            when 'month'
              datetime_value >> amount.to_i
            when 'day'
              datetime_value + Rational((amount.to_f * 86_400).round, 86_400)
            when 'hour'
              datetime_value + Rational((amount.to_f * 3_600).round, 86_400)
            when 'minute'
              datetime_value + Rational((amount.to_f * 60).round, 86_400)
            when 'second'
              datetime_value + Rational(amount.to_f.round, 86_400)
            else
              datetime_value + Rational((amount.to_f * 86_400).round, 86_400)
            end
          end

          # Builds concrete datetime grouped entries and attaches matching items.
          def build_datetime_entries_from_spans(spans, candidate_items, config)
            grouped_items = spans.each_with_object({}) { |span, memo| memo[span['index']] = [] }

            candidate_items.each do |entry|
              value = entry['value']
              span = spans.find do |candidate_span|
                range_value_within_span?(value, candidate_span['start'], candidate_span['end'], first_group: candidate_span['index'] == 1)
              end
              next if span.nil?

              grouped_items[span['index']] << entry['item']
            end

            entries = []
            spans.each do |span|
              items = grouped_items.fetch(span['index'])
              next if items.empty? && !config['empty']

              title_token = format_datetime_title_token(span['token_upper_bound'])
              permalink_token = format_datetime_permalink_token(span['token_upper_bound'], include_time: config['time_precision'])

              entry_filter = build_range_filter(
                min_value: span['start'],
                max_value: span['end'],
                min_inclusive: span['index'] == 1
              )

              entries << {
                'filters' => {
                  @key => entry_filter
                },
                'values' => {
                  @key => title_token
                },
                'token_values' => {
                  @key => {
                    'title' => title_token,
                    'permalink' => permalink_token
                  }
                },
                'group' => {
                  'mode' => 'datetime',
                  'start' => format_datetime_title_token(span['start']),
                  'end' => span['end'].nil? ? nil : format_datetime_title_token(span['end']),
                  'order' => span['index'],
                  'range' => true,
                  'other' => false
                },
                'items' => items.uniq
              }
            end

            entries
          end

          # Builds grouped entries for alphabetic mode.
          def build_alphabetic_entries(candidates, config)
            start_token = config['start']
            token_length = start_token.length
            start_index = alphabetic_token_to_index(start_token)
            step_size = config['step']
            empty_groups = config['empty']
            other_label = config['other']

            grouped_items = {}
            other_items = []

            candidates.each do |candidate|
              alpha_token = candidate['alpha'].to_s
              unless candidate['alpha_starts_with_letter']
                other_items << candidate['item'] unless other_label.nil? || other_label.empty?
                next
              end

              next if alpha_token.length < token_length

              candidate_token = alpha_token[0, token_length]
              candidate_index = alphabetic_token_to_index(candidate_token)
              next if candidate_index < start_index

              group_index = ((candidate_index - start_index) / step_size).floor + 1
              grouped_items[group_index] ||= []
              grouped_items[group_index] << candidate['item']
            end

            if grouped_items.empty? && (other_items.empty? || !empty_groups)
              return [] unless empty_groups
            end

            max_group_index = grouped_items.keys.max || 0
            if max_group_index > MAXIMUM_AUTOMATIC_GROUPS
              raise ArgumentError, "Grouped indexing implies more than #{MAXIMUM_AUTOMATIC_GROUPS} groups; alphabetic grouped indexing requires narrower ranges."
            end

            if max_group_index.zero? && empty_groups
              max_group_index = 1
            end

            entries = []

            (1..max_group_index).each do |group_index|
              group_items = grouped_items.fetch(group_index, [])
              next if group_items.empty? && !empty_groups

              range_start_index = start_index + ((group_index - 1) * step_size)
              range_end_index = range_start_index + step_size - 1
              range_start_token = alphabetic_index_to_token(range_start_index, token_length)
              range_end_token = alphabetic_index_to_token(range_end_index, token_length)

              include_tokens = (range_start_index..range_end_index).map do |token_index|
                alphabetic_index_to_token(token_index, token_length)
              end

              entries << {
                'filters' => {
                  @key => include_tokens.map { |token| "/^#{Regexp.escape(token)}/i" }
                },
                'values' => {
                  @key => range_start_token
                },
                'token_values' => {
                  @key => {
                    'title' => range_start_token,
                    'permalink' => range_start_token
                  }
                },
                'group' => {
                  'mode' => 'alphabetic',
                  'start' => range_start_token,
                  'end' => range_end_token,
                  'order' => group_index,
                  'range' => true,
                  'other' => false
                },
                'items' => group_items.uniq
              }
            end

            if !other_label.nil? && !other_label.empty? && (!other_items.empty? || empty_groups)
              entries << {
                'filters' => {
                  @key => '/^[^a-z]/i'
                },
                'values' => {
                  @key => other_label
                },
                'token_values' => {
                  @key => {
                    'title' => other_label,
                    'permalink' => other_label
                  }
                },
                'group' => {
                  'mode' => 'alphabetic',
                  'start' => other_label,
                  'end' => nil,
                  'order' => (entries.length + 1),
                  'range' => true,
                  'other' => true
                },
                'items' => other_items.uniq
              }
            end

            entries
          end

          # Normalises alphabetic start token and enforces max token length.
          def normalise_alphabetic_start(raw_start)
            token = normalise_alpha_value(raw_start)['letters']
            if token.empty?
              raise ArgumentError, '`group.start` for alphabetic grouping must begin with letters.'
            end

            token[0, MAXIMUM_ALPHABETIC_TOKEN_LENGTH]
          end

          # Converts an alphabetic token to a zero-based numeric index.
          def alphabetic_token_to_index(token)
            token.each_char.reduce(0) do |memo, character|
              (memo * 26) + (character.ord - 'a'.ord)
            end
          end

          # Converts a zero-based numeric index to an alphabetic token with a
          # fixed number of characters.
          def alphabetic_index_to_token(index, length)
            maximum_index = (26**length) - 1
            clamped_index = [[index.to_i, 0].max, maximum_index].min
            token_characters = Array.new(length, 'a')
            cursor = clamped_index

            (length - 1).downto(0) do |position|
              token_characters[position] = (('a'.ord + (cursor % 26)).chr)
              cursor /= 26
            end

            token_characters.join
          end

          # Checks value inclusion for one span, using first-group inclusive
          # lower bounds and subsequent-group exclusive lower bounds.
          def range_value_within_span?(value, min_value, max_value, first_group:)
            if first_group
              return false if value < min_value
            else
              return false if value <= min_value
            end

            return true if max_value.nil?
            return false if value > max_value

            true
          end

          # Builds one range filter hash with the required min/max mode.
          def build_range_filter(min_value:, max_value:, min_inclusive:)
            filter = {}
            filter['min'] = min_value unless min_value.nil?
            filter['max'] = max_value unless max_value.nil?

            if max_value.nil?
              filter['mode'] = min_inclusive ? 'min-inclusive' : 'min-exclusive'
            elsif min_inclusive
              filter['mode'] = 'min-inclusive max-inclusive'
            else
              filter['mode'] = 'min-exclusive max-inclusive'
            end

            filter
          end

          # Formats numeric placeholder values compactly without losing
          # significant decimal precision.
          def format_numeric_token(value)
            numeric = value.to_f
            return numeric.to_i.to_s if (numeric % 1.0).zero?

            formatted = format('%.10f', numeric)
            formatted.sub(/0+\z/, '').sub(/\.\z/, '')
          end

          # Formats datetime token values for title placeholders.
          def format_datetime_title_token(value)
            value.strftime('%Y-%m-%d %H:%M:%S %z')
          end

          # Formats datetime token values for permalink placeholders.
          def format_datetime_permalink_token(value, include_time:)
            if include_time
              value.strftime('%Y-%m-%d-%H-%M-%S')
            else
              value.strftime('%Y-%m-%d')
            end
          end

          # Derives a default datetime start from observed values.
          #
          # Default behaviour:
          # - earliest candidate datetime
          # - aligned to a natural unit boundary based on step unit
          def infer_default_datetime_start(candidates, first_step)
            earliest_value = candidates.map { |candidate| candidate['datetime'] }.compact.min
            earliest_value = DateTime.now unless earliest_value.is_a?(DateTime)

            case first_step['unit']
            when 'year'
              DateTime.new(earliest_value.year, 1, 1, 0, 0, 0, earliest_value.offset)
            when 'month'
              DateTime.new(earliest_value.year, earliest_value.month, 1, 0, 0, 0, earliest_value.offset)
            when 'day'
              DateTime.new(earliest_value.year, earliest_value.month, earliest_value.day, 0, 0, 0, earliest_value.offset)
            when 'hour'
              DateTime.new(earliest_value.year, earliest_value.month, earliest_value.day, earliest_value.hour, 0, 0, earliest_value.offset)
            when 'minute'
              DateTime.new(earliest_value.year, earliest_value.month, earliest_value.day, earliest_value.hour, earliest_value.min, 0, earliest_value.offset)
            when 'second'
              DateTime.new(earliest_value.year, earliest_value.month, earliest_value.day, earliest_value.hour, earliest_value.min, earliest_value.sec, earliest_value.offset)
            else
              earliest_value
            end
          end

          # Interprets `now`/`today` keyword expressions with optional offsets.
          def interpret_datetime_keyword_expression(value, range_key:)
            expression = value.to_s.strip
            return nil if expression.empty?

            now_pattern = Regexp.escape(@now_keyword)
            now_match = expression.match(/\A#{now_pattern}(?:\s*([+-])\s*(\d+))?\z/i)
            unless now_match.nil?
              offset_seconds = now_match[2].nil? ? 0 : now_match[2].to_i
              offset_seconds = -offset_seconds if now_match[1] == '-'
              return DateTime.now + Rational(offset_seconds, 86_400)
            end

            today_pattern = Regexp.escape(@today_keyword)
            today_match = expression.match(/\A#{today_pattern}(?:\s*([+-])\s*(\d+))?\z/i)
            return nil if today_match.nil?

            offset_days = today_match[2].nil? ? 0 : today_match[2].to_i
            offset_days = -offset_days if today_match[1] == '-'

            current_time = DateTime.now
            target_date = current_time.to_date + offset_days

            if range_key == 'max'
              DateTime.new(target_date.year, target_date.month, target_date.day, 23, 59, 59, current_time.offset)
            else
              DateTime.new(target_date.year, target_date.month, target_date.day, 0, 0, 0, current_time.offset)
            end
          end

          # Interprets anchor expressions such as `year(today)` and `month(now)`.
          def interpret_datetime_anchor_expression(value)
            stripped = value.to_s.strip
            match = stripped.match(/\A(#{duration_keywords_pattern})\s*\((.+)\)\z/i)
            return nil if match.nil?

            unit = canonical_duration_unit(match[1])
            inner = match[2].to_s.strip
            anchor_time = interpret_datetime_keyword_expression(inner, range_key: 'min')
            return nil if anchor_time.nil?

            case unit
            when 'year'
              DateTime.new(anchor_time.year, 1, 1, 0, 0, 0, anchor_time.offset)
            when 'month'
              DateTime.new(anchor_time.year, anchor_time.month, 1, 0, 0, 0, anchor_time.offset)
            when 'day'
              DateTime.new(anchor_time.year, anchor_time.month, anchor_time.day, 0, 0, 0, anchor_time.offset)
            when 'hour'
              DateTime.new(anchor_time.year, anchor_time.month, anchor_time.day, anchor_time.hour, 0, 0, anchor_time.offset)
            when 'minute'
              DateTime.new(anchor_time.year, anchor_time.month, anchor_time.day, anchor_time.hour, anchor_time.min, 0, anchor_time.offset)
            when 'second'
              DateTime.new(anchor_time.year, anchor_time.month, anchor_time.day, anchor_time.hour, anchor_time.min, anchor_time.sec, anchor_time.offset)
            else
              nil
            end
          end
        end
      end
    end
  end
end
