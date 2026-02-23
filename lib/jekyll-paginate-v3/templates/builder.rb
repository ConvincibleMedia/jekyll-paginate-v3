# frozen_string_literal: true

module Jekyll
  module Plugins
    module PaginateV3
      module Templates
        # Builds generated pagination templates from `pagination.templates.generate`.
        #
        # Generated templates are ordinary pages/documents with
        # `pagination.enabled: true`, so the core pagination model can process
        # them exactly like hand-written pagination templates.
        #
        # Used by Pagination::Model before normal page pagination starts.
        class Builder
          SPECIAL_KEYS = %w[items index filter filters layout layouts location frontmatter permalink title slugify silent allow_empty].freeze

          def initialize(site:, site_config:, add_item_lambda:, resolve_items_lambda:, log_lambda:)
            @site = site
            @site_config = site_config
            @add_item_lambda = add_item_lambda
            @resolve_items_lambda = resolve_items_lambda
            @log_lambda = log_lambda
            @nested_separator = site_config['nested_key_separator']
            @equivalents = site_config['equivalents']
            @compatibility_mode = site_config['compatibility']
          end

          # Builds all configured generated pagination templates.
          def build
            generate_definitions = @site_config.dig('templates', 'generate')
            return 0 unless generate_definitions.is_a?(Array)

            @log_lambda.call("Generating templates from #{generate_definitions.length} definition(s).", 'debug')
            default_location = default_generation_location
            @log_lambda.call("Default generated template location resolved to '#{default_location}'.", 'debug')
            generated_count = 0

            generate_definitions.each_with_index do |raw_definition, definition_index|
              definition = normalise_definition(raw_definition, default_location)
              next if definition.nil?

              @log_lambda.call("Processing generate definition #{definition_index + 1}: index=#{definition['index'].join(', ')} items=#{definition['items']} layouts=#{definition['layouts'].join(', ')} location=#{definition['location']} allow_empty=#{definition['allow_empty']}", 'debug')
              source_items = @resolve_items_lambda.call(definition['items'])
              @log_lambda.call("Definition #{definition_index + 1} resolved #{source_items.length} source item(s) before filters.", 'debug')
              source_items = Query::Filter.filter_items(
                source_items,
                definition['filters'],
                nested_separator: @nested_separator,
                equivalents: @equivalents,
                split_delimiter: @site_config['split'],
                now_keyword: @site_config.dig('keywords', 'now'),
                log_lambda: @log_lambda
              )
              @log_lambda.call("Definition #{definition_index + 1} retained #{source_items.length} source item(s) after filters.", 'debug')

              generated_count += build_for_definition(definition, source_items)
            end

            @log_lambda.call("Generated #{generated_count} template object(s) in total.", 'debug')
            generated_count
          end

          private

          # Expands one generate definition into concrete template pages/documents.
          def build_for_definition(definition, source_items)
            entries = build_index_entries(source_items, definition)
            if entries.empty?
              @log_lambda.call("No index entries were generated for index=#{definition['index'].join(', ')}.", 'debug')
              return 0
            end

            @log_lambda.call("Expanded to #{entries.length} index key combination(s) for index=#{definition['index'].join(', ')}.", 'debug')

            created = 0
            entries.each do |entry|
              definition['layouts'].each do |layout_name|
                page = build_template(definition, entry, layout_name)
                next if page.nil?

                @add_item_lambda.call(page)
                @log_lambda.call("Created generated template for layout='#{layout_name}' values=#{entry['values']}.", 'debug')
                created += 1
              end
            end

            created
          end

          # Builds a single template object for one index value tuple and layout.
          def build_template(definition, entry, layout_name)
            token_map = build_token_map(definition['index'], entry['values'], slugify_config: definition['slugify'])
            generated_permalink = Utils.replace_tokens(definition['permalink'], token_map)
            generated_title = Utils.replace_tokens(definition['title'], token_map)
            generated_metadata = build_generated_metadata(definition['index'], entry['values'], token_map)

            generated_frontmatter = Utils.deep_copy(definition['frontmatter'])
            generated_frontmatter['title'] = generated_title unless generated_title.nil? || generated_title.empty?
            generated_frontmatter['permalink'] = generated_permalink unless generated_permalink.nil? || generated_permalink.empty?

            pagination_config = Utils.deep_copy(definition['pagination_overrides'])
            pagination_config['enabled'] = true
            pagination_config['items'] = definition['items']
            pagination_config['filters'] = Utils.deep_copy(definition['filters']).merge(entry['filters'])

            if definition['location'] == 'pages'
              Templates::PageTemplate.new(
                site: @site,
                layout_name: layout_name,
                pagination_config: pagination_config,
                frontmatter: generated_frontmatter,
                generated_metadata: generated_metadata
              )
            else
              collection = @site.collections[definition['location']]
              if collection.nil?
                @log_lambda.call("Skipping generated template in unknown collection '#{definition['location']}'.", 'warn') unless definition['silent']
                return nil
              end

              Templates::DocumentTemplate.new(
                site: @site,
                collection: collection,
                layout_name: layout_name,
                pagination_config: pagination_config,
                frontmatter: generated_frontmatter,
                generated_metadata: generated_metadata
              )
            end
          rescue StandardError => error
            @log_lambda.call("Unable to generate template from layout '#{layout_name}': #{error.message}", 'warn') unless definition['silent']
            nil
          end

          # Recursively groups items by index keys to produce one entry per
          # unique key/value combination.
          def build_index_entries(items, definition)
            entries = []
            recurse_build_entries(items, definition, 0, {}, {}, entries)
            add_empty_collection_entries(entries, definition)
          end

          # Depth-first grouping for multi-level indexes such as
          # `index: category, subcategory`.
          def recurse_build_entries(items, definition, depth, active_filters, active_values, entries)
            index_keys = definition['index']
            if depth >= index_keys.length
              entries << {
                'filters' => active_filters,
                'values' => active_values
              }
              return
            end

            key = index_keys[depth]
            grouped_items = group_items_by_key(items, key, slugify_config: definition['slugify'])

            grouped_items.each do |group|
              next if group['token'].nil? || group['token'].empty?

              next_filters = active_filters.merge(key => group['filter_value'])
              next_values = active_values.merge(key => group['display_name'])
              recurse_build_entries(group['items'], definition, depth + 1, next_filters, next_values, entries)
            end
          end

          # Groups items by one frontmatter key (supports nested/equivalent keys).
          def group_items_by_key(items, key, slugify_config:)
            equivalent_lookup = Utils.build_equivalent_lookup(@equivalents)
            grouped = {}

            items.each do |item|
              values = values_for_key(item, key, equivalent_lookup)
              values.each do |value|
                token = slugify_value(value, slugify_config)
                next if token.empty?

                group = grouped[token]
                if group.nil?
                  group = {
                    'token' => token,
                    'display_name' => value,
                    'raw_values' => [],
                    'items' => []
                  }
                  grouped[token] = group
                end

                group['raw_values'] << value unless group['raw_values'].include?(value)
                group['items'] << item
              end
            end

            grouped.values.map do |group|
              {
                'token' => group['token'],
                'display_name' => group['display_name'],
                'filter_value' => group['raw_values'].length == 1 ? group['raw_values'].first : group['raw_values'],
                'items' => group['items'].uniq
              }
            end.sort_by { |group| group['token'] }
          end

          # Extracts unique scalar values for a key, including delimiter-defined
          # string lists.
          def values_for_key(item, key, equivalent_lookup)
            data = item.respond_to?(:data) && item.data.is_a?(Hash) ? item.data.dup : {}
            collection_label = Utils.item_collection_label(item)
            data['collection'] = collection_label unless collection_label.nil?

            values = Utils.fetch_nested_values(data, key, @nested_separator, equivalent_lookup)
            values = values.flat_map do |value|
              if value.is_a?(String)
                Utils.split_delimited_string(value, @site_config['split'])
              else
                Utils.scalar_values(value)
              end
            end

            values.map { |value| value.to_s.strip }.reject(&:empty?).uniq
          end

          # Normalises one raw `templates.generate` definition into a predictable
          # internal shape.
          def normalise_definition(raw_definition, default_location)
            definition = Utils.safe_hash(raw_definition)
            return nil if definition.empty?
            silent = normalise_boolean(definition['silent'])

            index_keys = Utils.delimited_array(definition['index'], delimiter: @site_config['split']).map { |key| key.to_s.strip }.reject(&:empty?)
            if index_keys.empty?
              @log_lambda.call('Skipping generated index config with missing `index` key.', 'warn') unless silent
              return nil
            end

            duplicated_keys = index_keys.group_by { |key| key }.select { |_, values| values.length > 1 }.keys
            unless duplicated_keys.empty?
              raise ArgumentError, "Generated index config contains duplicate `index` key(s): #{duplicated_keys.join(', ')}."
            end

            layouts = Utils.normalise_layouts(definition, split_delimiter: @site_config['split'])
            if layouts.empty?
              @log_lambda.call('Skipping generated index config with no `layout`/`layouts` value.', 'warn') unless silent
              return nil
            end

            filters = Utils.safe_hash(definition['filters'])
            if definition.key?('filter')
              index_keys.each { |key| filters[key] = definition['filter'] unless filters.key?(key) }
            end

            {
              'items' => definition['items'].nil? ? @site_config['items'] : definition['items'],
              'index' => index_keys,
              'filters' => filters,
              'layouts' => layouts,
              'location' => normalise_location(definition['location'], default_location),
              'frontmatter' => Utils.safe_hash(definition['frontmatter']),
              'permalink' => definition['permalink'].to_s,
              'title' => definition['title'].to_s,
              'slugify' => normalise_slugify_config(definition['slugify']),
              'silent' => silent,
              'allow_empty' => normalise_boolean(definition['allow_empty']),
              'pagination_overrides' => extract_pagination_overrides(definition)
            }
          end

          # Splits non-special keys from a generate definition so they can be
          # merged into the generated template's pagination config.
          def extract_pagination_overrides(definition)
            overrides = Utils.safe_hash(definition).reject { |key, _| SPECIAL_KEYS.include?(key) }

            # `permalink` and `title` on generate definitions are page-level values
            # for generated templates, not paginator suffix patterns.
            overrides
          end

          def normalise_location(raw_location, default_location)
            location = raw_location.to_s.strip
            return default_location if location.empty?

            return 'pages' if location == 'pages'
            return default_location if location == 'all' || location == 'everything'

            location
          end

          # Uses `templates.location` to infer whether generated templates should
          # default to `pages` or a collection.
          def default_generation_location
            first_type = Query::Parser.first_type(@site_config.dig('templates', 'location'), @site_config['keywords'], split_delimiter: @site_config['split'])
            return 'pages' if first_type.nil?
            return 'pages' if %w[pages all everything].include?(first_type)

            first_type
          end

          # Builds placeholder values used by generated `permalink` and `title`
          # strings.
          def build_token_map(index_keys, values, slugify_config:)
            token_map = {}

            index_keys.each do |key|
              value = values[key]
              token_map[key] = slugify_value(value, slugify_config)
            end

            apply_legacy_token_aliases!(token_map, index_keys)
            token_map
          end

          # Applies v2 legacy token aliases (`:coll`, `:cat`, `:tag`) for
          # generated title/permalink placeholders.
          def apply_legacy_token_aliases!(token_map, index_keys)
            if @compatibility_mode == 'v2'
              if index_keys.include?('collection')
                token_map['coll'] = token_map['collection']
              end

              if index_keys.include?('category') || index_keys.include?('categories')
                token_map['cat'] = token_map['category'] || token_map['categories']
              end

              if index_keys.include?('tag') || index_keys.include?('tags')
                token_map['tag'] = token_map['tag'] || token_map['tags']
              end
            end
          end

          # Normalises slugify config accepted on `templates.generate[]`.
          # This uses v2 naming (`slugify.case`) for case-sensitive tokens.
          def normalise_slugify_config(raw_slugify)
            slugify = Utils.safe_hash(raw_slugify)
            mode = slugify['mode'].to_s.strip
            mode = 'default' if mode.empty?

            case_sensitive = normalise_boolean(slugify['case'])

            {
              'mode' => mode,
              'case' => case_sensitive
            }
          end

          # Slugifies one token value according to an index definition.
          def slugify_value(value, slugify_config)
            mode = slugify_config['mode']
            case_sensitive = slugify_config['case']
            Jekyll::Utils.slugify(value.to_s, mode: mode, cased: case_sensitive)
          end

          # Coerces loose truthy/falsey config values to a strict boolean.
          def normalise_boolean(value)
            return value if value == true || value == false

            value.to_s.strip.casecmp('true').zero?
          end

          # Captures generated-template metadata for compatibility and template use.
          def build_generated_metadata(index_keys, raw_values, token_map)
            metadata = {
              'generated_template' => true,
              'index_keys' => index_keys,
              'tokens' => Utils.deep_copy(raw_values),
              'compatibility' => @compatibility_mode
            }

            if @compatibility_mode == 'v2' && index_keys.length == 1
              key = index_keys.first
              metadata['autopages'] = {
                'key' => key,
                'value' => token_map[key],
                'display_name' => raw_values[key].to_s
              }
            end

            metadata
          end

          # Adds synthetic entries for empty collections when `allow_empty` is enabled
          # on a single-level `collection` index definition.
          def add_empty_collection_entries(entries, definition)
            return entries unless definition['allow_empty']
            unless definition['index'] == ['collection']
              @log_lambda.call("`allow_empty` is only applicable for `index: collection`; skipping for index=#{definition['index'].join(', ')}.", 'warn') unless definition['silent']
              return entries
            end

            expected_labels = expected_collection_labels(definition['items'])
            existing_labels = entries.map { |entry| entry.dig('values', 'collection').to_s }.reject(&:empty?).uniq
            added = 0

            expected_labels.each do |collection_label|
              next if existing_labels.include?(collection_label)
              next unless @site.collections.key?(collection_label)
              next unless @site.collections[collection_label].docs.empty?

              entries << {
                'filters' => { 'collection' => collection_label },
                'values' => { 'collection' => collection_label }
              }
              added += 1
            end

            @log_lambda.call("Added #{added} empty collection index entry/entries.", 'debug') if added.positive?
            entries
          end

          # Determines which collections are targeted by an `items` search definition.
          def expected_collection_labels(raw_items)
            labels = []
            Query::Parser.parse(raw_items, @site_config['keywords'], split_delimiter: @site_config['split']).each do |entry|
              case entry['type']
              when 'all', 'everything'
                labels.concat(@site.collections.keys)
              when 'pages'
                # pages do not map to collections
              else
                labels << entry['type'] if @site.collections.key?(entry['type'])
              end
            end

            labels.uniq
          end
        end
      end
    end
  end
end
