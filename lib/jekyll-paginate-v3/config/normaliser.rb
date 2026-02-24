# frozen_string_literal: true

module Jekyll
  module Plugins
    module PaginateV3
      module Config
        # Normalises site and template pagination config into predictable
        # internal structures consumed by pagination runtime classes.
        #
        # Site-level config is normalised to the nested public v3 structure:
        # - pagination.syntax.*
        # - pagination.templates.location
        # - pagination.templates.generate
        # - pagination.templates.defaults.*
        #
        # Template-level config is normalised to a flat hash used during
        # pagination emission for one concrete template page/document.
        class Normaliser
          LEGACY_FILTER_KEYS = %w[category tag locale].freeze
          LEGACY_TEMPLATE_DEFAULT_KEYS = %w[items filters sort per_page limit offset trail title permalink sort_field sort_reverse indexpage extension].freeze
          LEGACY_SITE_KEY_ALIASES = %w[split separator nested_key_separator].freeze
          V2_AUTOPAGE_DEFAULTS = {
            'tags' => {
              'layout' => 'autopage_tags.html',
              'title' => 'Posts tagged with :tag',
              'permalink' => '/tag/:tag',
              'slugify' => {
                'mode' => 'default',
                'case' => false
              }
            },
            'categories' => {
              'layout' => 'autopage_category.html',
              'title' => 'Posts in category :cat',
              'permalink' => '/category/:cat',
              'slugify' => {
                'mode' => 'default',
                'case' => false
              }
            },
            'collections' => {
              'layout' => 'autopage_collection.html',
              'title' => 'Posts in collection :coll',
              'permalink' => '/collection/:coll/',
              'slugify' => {
                'mode' => 'default',
                'case' => false
              }
            }
          }.freeze

          # Produces canonical site-level pagination config.
          #
          # Merge order:
          # defaults -> compatibility profile -> legacy overlays -> user config.
          def self.normalise_site_config(site_config)
            site_hash = Utils.safe_hash(site_config)
            raw_pagination = normalise_site_pagination_source(site_hash['pagination'])

            compatibility_mode = normalise_compatibility(raw_pagination['compatibility'])

            config = Utils.deep_copy(DEFAULTS)
            if compatibility_mode && COMPATIBILITY_PROFILES.key?(compatibility_mode)
              config = Jekyll::Utils.deep_merge_hashes(config, Utils.deep_copy(COMPATIBILITY_PROFILES[compatibility_mode]))
            end

            if compatibility_mode == 'v1'
              config = Jekyll::Utils.deep_merge_hashes(config, legacy_v1_overlay(site_hash))
            end

            config = Jekyll::Utils.deep_merge_hashes(config, raw_pagination)
            config['compatibility'] = compatibility_mode unless compatibility_mode.nil?

            normalise_site_common!(config, compatibility_mode, raw_pagination)
            migrate_legacy_shortcuts!(config.dig('templates', 'defaults'), compatibility_mode, raw_pagination)
            apply_v2_legacy_page_templates!(config.dig('templates', 'defaults'), raw_pagination, compatibility_mode)
            migrate_v2_autopages!(config, site_hash['autopages'], compatibility_mode)

            config
          end

          # Produces template-level pagination config used while paginating one
          # template page/document.
          #
          # The output is intentionally flat so downstream pipeline code can read
          # values directly without re-resolving site defaults.
          def self.normalise_template_config(site_config, template_pagination_config)
            raw_template_pagination = Utils.safe_hash(template_pagination_config)
            compatibility_mode = normalise_compatibility(raw_template_pagination['compatibility']) || normalise_compatibility(site_config['compatibility'])
            site_template_defaults = Utils.safe_hash(site_config.dig('templates', 'defaults'))

            page_config = Jekyll::Utils.deep_merge_hashes(
              Utils.deep_copy(site_template_defaults),
              raw_template_pagination
            )

            page_config['enabled'] = if raw_template_pagination.key?('enabled')
                                       !!raw_template_pagination['enabled']
                                     else
                                       !!site_config['enabled']
                                     end
            page_config['compatibility'] = compatibility_mode unless compatibility_mode.nil?

            syntax = resolve_template_syntax(raw_template_pagination, site_config['syntax'])
            page_config['split'] = syntax['split']
            page_config['separator'] = syntax['separator']

            page_config = normalise_template_defaults(
              page_config,
              raw_overrides: raw_template_pagination,
              split_delimiter: syntax['split']
            )

            migrate_legacy_shortcuts!(page_config, compatibility_mode, raw_template_pagination)
            apply_v2_legacy_page_templates!(page_config, raw_template_pagination, compatibility_mode)

            page_config
          end

          class << self
            private

            # Maps old top-level v3 keys onto nested modern locations while
            # preserving legacy v2 shortcut fields at the top level.
            def normalise_site_pagination_source(raw_pagination)
              source = Utils.deep_copy(Utils.safe_hash(raw_pagination))

              syntax = Utils.safe_hash(source['syntax'])
              syntax['split'] = source['split'] if source.key?('split') && !syntax.key?('split')
              syntax['separator'] = source['separator'] if source.key?('separator') && !syntax.key?('separator')
              if source.key?('nested_key_separator') && !syntax.key?('separator') && !syntax.key?('nested_key_separator')
                syntax['separator'] = source['nested_key_separator']
              end
              source['syntax'] = syntax unless syntax.empty?

              templates = Utils.safe_hash(source['templates'])
              template_defaults = Utils.safe_hash(templates['defaults'])
              LEGACY_TEMPLATE_DEFAULT_KEYS.each do |legacy_key|
                next unless source.key?(legacy_key)
                next if template_defaults.key?(legacy_key)

                template_defaults[legacy_key] = source[legacy_key]
              end
              templates['defaults'] = template_defaults unless template_defaults.empty?
              source['templates'] = templates unless templates.empty?

              LEGACY_SITE_KEY_ALIASES.each { |legacy_key| source.delete(legacy_key) }
              LEGACY_TEMPLATE_DEFAULT_KEYS.each { |legacy_key| source.delete(legacy_key) }

              source
            end

            def normalise_site_common!(config, compatibility_mode, raw_overrides = nil)
              config['enabled'] = !!config['enabled']
              config['debug'] = !!config['debug']
              config['compatibility'] = compatibility_mode if compatibility_mode

              config['syntax'] = normalise_syntax(config['syntax'])
              split_delimiter = config.dig('syntax', 'split')

              config['keywords'] = normalise_keywords(config['keywords'])
              config['equivalents'] = normalise_equivalents(config['equivalents'], split_delimiter)
              config['templates'] = normalise_templates(config['templates'], split_delimiter: split_delimiter, raw_overrides: raw_overrides)
            end

            # Resolves template syntax from local overrides, accepting both the
            # modern nested syntax hash and legacy root aliases.
            def resolve_template_syntax(raw_template_pagination, site_syntax)
              syntax = normalise_syntax(raw_template_pagination['syntax'], fallback: site_syntax)

              if raw_template_pagination.key?('split')
                syntax['split'] = normalise_split(raw_template_pagination['split'], syntax['split'])
              end

              if raw_template_pagination.key?('separator')
                separator = raw_template_pagination['separator'].to_s
                syntax['separator'] = separator.strip.empty? ? syntax['separator'] : separator
              elsif raw_template_pagination.key?('nested_key_separator')
                separator = raw_template_pagination['nested_key_separator'].to_s
                syntax['separator'] = separator.strip.empty? ? syntax['separator'] : separator
              end

              syntax
            end

            def normalise_syntax(raw_syntax, fallback: nil)
              defaults = Utils.deep_copy(DEFAULTS['syntax'])
              defaults = defaults.merge(Utils.safe_hash(fallback)) if fallback.is_a?(Hash)
              syntax = defaults.merge(Utils.safe_hash(raw_syntax))

              separator = syntax['separator']
              if (separator.nil? || separator.to_s.strip.empty?) && syntax.key?('nested_key_separator')
                separator = syntax['nested_key_separator']
              end
              separator = defaults['separator'] if separator.to_s.strip.empty?

              {
                'separator' => separator.to_s,
                'split' => normalise_split(syntax['split'], defaults['split'])
              }
            end

            def normalise_compatibility(raw_value)
              value = raw_value.to_s.strip.downcase
              return nil if value.empty?
              return value if %w[v1 v2].include?(value)

              nil
            end

            def normalise_split(raw_split, default_split = DEFAULTS.dig('syntax', 'split'))
              Utils.normalise_split_delimiter(raw_split, default_split)
            end

            def normalise_keywords(raw_keywords)
              defaults = Utils.deep_copy(KEYWORD_DEFAULTS)
              keywords = defaults.merge(Utils.safe_hash(raw_keywords))

              keywords.each do |key, value|
                keywords[key] = value.to_s.strip
                keywords[key] = defaults[key] if keywords[key].empty?
              end

               invalid_keywords = keywords.select { |_, value| !value.match?(/\A[a-z]+\z/) }
               unless invalid_keywords.empty?
                 raise ArgumentError, "pagination.keywords values must match [a-z]+. Invalid entries: #{invalid_keywords.map { |key, value| "#{key}=#{value}" }.join(', ')}."
               end

               duplicate_values = keywords.values.group_by { |value| value }.select { |_, values| values.length > 1 }.keys
               unless duplicate_values.empty?
                 raise ArgumentError, "pagination.keywords values must be unique. Duplicates: #{duplicate_values.join(', ')}."
               end

              keywords
            end

            def normalise_equivalents(raw_equivalents, split_delimiter)
              return false if raw_equivalents == false

              groups = if raw_equivalents.is_a?(Array)
                         raw_equivalents
                       elsif raw_equivalents.nil?
                         []
                       else
                         [raw_equivalents]
                       end
              return Utils.deep_copy(DEFAULTS['equivalents']) if groups.empty?

              groups.map do |group|
                entries = if group.is_a?(Array)
                            group.flat_map { |entry| Utils.delimited_array(entry, delimiter: split_delimiter) }
                          else
                            Utils.delimited_array(group, delimiter: split_delimiter)
                          end

                entries.map { |entry| entry.to_s.strip }.reject(&:empty?).uniq
              end.reject { |group| group.length < 2 }
            end

            def normalise_templates(raw_templates, split_delimiter:, raw_overrides:)
              defaults = Utils.deep_copy(DEFAULTS['templates'])
              source = defaults.merge(Utils.safe_hash(raw_templates))

              source['location'] = defaults['location'] if source['location'].nil? || source['location'].to_s.strip.empty?
              source['generate'] = if source['generate'].is_a?(Array)
                                     source['generate'].map { |entry| Utils.safe_hash(entry) }
                                   elsif source['generate'].is_a?(Hash)
                                     [Utils.safe_hash(source['generate'])]
                                   else
                                     []
                                   end

              merged_defaults = Jekyll::Utils.deep_merge_hashes(
                Utils.safe_hash(defaults['defaults']),
                Utils.safe_hash(source['defaults'])
              )
              source['defaults'] = normalise_template_defaults(
                merged_defaults,
                raw_overrides: extract_template_defaults_overrides(raw_overrides),
                split_delimiter: split_delimiter
              )

              source
            end

            # Extracts template-default override keys from either modern nested
            # config or legacy top-level aliases.
            def extract_template_defaults_overrides(raw_overrides)
              override_hash = Utils.safe_hash(raw_overrides)
              template_overrides = Utils.safe_hash(Utils.safe_hash(override_hash['templates'])['defaults'])

              LEGACY_TEMPLATE_DEFAULT_KEYS.each do |legacy_key|
                next unless override_hash.key?(legacy_key)
                next if template_overrides.key?(legacy_key)

                template_overrides[legacy_key] = override_hash[legacy_key]
              end

              template_overrides
            end

            # Normalises one template-default hash (used by site defaults and
            # by per-template runtime config).
            def normalise_template_defaults(template_defaults, raw_overrides:, split_delimiter:)
              config = Utils.safe_hash(template_defaults)
              template_override_hash = extract_template_defaults_overrides(raw_overrides)
              sort_explicitly_set = template_override_hash.key?('sort') && present_config_value?(template_override_hash['sort'])

              config['items'] = normalise_items_value(config['items'])
              config['filters'] = Utils.safe_hash(config['filters'])
              config['offset'] = [config['offset'].to_i, 0].max
              config['per_page'] = normalise_per_page(config['per_page'], split_delimiter: split_delimiter)
              config['limit'] = [config['limit'].to_i, 0].max
              config['permalink'] = config['permalink'].to_s
              config['title'] = config['title'].to_s
              config['trail'] = normalise_trail(config['trail'])
              config['sort'] = normalise_sort(
                config['sort'],
                config['sort_field'],
                config['sort_reverse'],
                split_delimiter,
                sort_explicitly_set: sort_explicitly_set
              )
              config['page_templates'] = build_page_templates(config['title'], config['permalink'])

              config.delete('sort_field')
              config.delete('sort_reverse')
              config.delete('indexpage')
              config.delete('extension')

              config
            end

            # Builds internal page template settings.
            #
            # Page 1 defaults to inheriting title/location from the source
            # template, while page 2+ uses configured paginator patterns.
            def build_page_templates(page2_title, page2_permalink)
              {
                'page1' => {
                  'title' => ':title',
                  'permalink' => ''
                },
                'page2' => {
                  'title' => page2_title.to_s,
                  'permalink' => page2_permalink.to_s
                }
              }
            end

            def normalise_items_value(raw_items)
              return DEFAULTS.dig('templates', 'defaults', 'items') if raw_items.nil?
              return raw_items if raw_items.is_a?(Hash) || raw_items.is_a?(Array)

              value = raw_items.to_s.strip
              value.empty? ? DEFAULTS.dig('templates', 'defaults', 'items') : value
            end

            def normalise_trail(raw_trail)
              trail = Utils.safe_hash(raw_trail)
              {
                'before' => [trail['before'].to_i, 0].max,
                'after' => [trail['after'].to_i, 0].max
              }
            end

            # Normalises per-page configuration.
            #
            # Accepts:
            # - Integer-like values
            # - Array values
            # - Delimited strings (using configured split delimiter)
            #
            # Returns either:
            # - Integer, for single-size pagination
            # - Array<Integer>, for variable per-page pagination patterns
            def normalise_per_page(raw_per_page, split_delimiter:)
              if raw_per_page.is_a?(Array)
                return Utils.normalise_per_page_pattern(raw_per_page)
              end

              if raw_per_page.is_a?(String)
                split_values = Utils.delimited_array(raw_per_page, delimiter: split_delimiter)
                if split_values.length > 1
                  return Utils.normalise_per_page_pattern(split_values)
                end
              end

              Utils.normalise_per_page_pattern(raw_per_page).first
            end

            # Preserves legacy `sort_field` + `sort_reverse` behaviour when the
            # caller did not provide an explicit `sort` override.
            def normalise_sort(raw_sort, raw_sort_field, raw_sort_reverse, split_delimiter, sort_explicitly_set: false)
              sort_entries = Utils.arrayify(raw_sort, split_delimiter: split_delimiter).map(&:to_s).map(&:strip).reject(&:empty?)
              sort_field = raw_sort_field.to_s.strip

              if !sort_explicitly_set && !sort_field.empty?
                direction = boolean_config_value(raw_sort_reverse) ? 'desc' : 'asc'
                return ["#{sort_field} #{direction}"]
              end

              return sort_entries unless sort_entries.empty?

              if sort_field.empty?
                fallback_sort = DEFAULTS.dig('templates', 'defaults', 'sort')
                return Utils.arrayify(fallback_sort, split_delimiter: split_delimiter).map(&:to_s).map(&:strip).reject(&:empty?)
              end

              direction = boolean_config_value(raw_sort_reverse) ? 'desc' : 'asc'
              ["#{sort_field} #{direction}"]
            end

            # Migrates old v2 shorthand config into canonical template fields.
            # Modern keys retain precedence when both forms are supplied.
            def migrate_legacy_shortcuts!(template_config, compatibility_mode, raw_overrides = nil)
              return unless compatibility_mode == 'v2'

              override_hash = Utils.safe_hash(raw_overrides)
              template_overrides = extract_template_defaults_overrides(override_hash)
              explicit_filters = Utils.safe_hash(template_overrides['filters'])

              if override_hash.key?('collection') && present_config_value?(override_hash['collection']) && !template_overrides.key?('items')
                template_config['items'] = override_hash['collection']
              end

              LEGACY_FILTER_KEYS.each do |legacy_key|
                next unless override_hash.key?(legacy_key)
                next unless present_config_value?(override_hash[legacy_key])
                next if explicit_filters.key?(legacy_key)
                next if legacy_key == 'category' && override_hash[legacy_key].to_s.strip == 'posts'

                template_config['filters'][legacy_key] = override_hash[legacy_key]
              end

              template_config.delete('collection')
              LEGACY_FILTER_KEYS.each { |legacy_key| template_config.delete(legacy_key) }
            end

            # Applies v2 `indexpage`/`extension` legacy behaviour by translating
            # those keys into internal page1/page2 permalink templates.
            def apply_v2_legacy_page_templates!(template_config, raw_overrides, compatibility_mode)
              return unless compatibility_mode == 'v2'

              override_hash = extract_template_defaults_overrides(raw_overrides)
              return unless override_hash.key?('indexpage') || override_hash.key?('extension')

              index_name = override_hash.key?('indexpage') ? override_hash['indexpage'].to_s : 'index'
              extension = override_hash.key?('extension') ? override_hash['extension'].to_s : 'html'

              template_config['page_templates'] ||= build_page_templates(template_config['title'], template_config['permalink'])
              template_config['page_templates']['page1']['permalink'] = Utils.ensure_full_path('/', index_name, extension)
              template_config['page_templates']['page2']['permalink'] = Utils.ensure_full_path(template_config['permalink'], index_name, extension)
            end

            # Imports legacy top-level `paginate` settings used by
            # jekyll-paginate v1.
            def legacy_v1_overlay(site_hash)
              overlay = {}
              return overlay if site_hash['paginate'].nil?

              overlay['enabled'] = true
              overlay['keywords'] = { 'items' => 'posts' }
              overlay['templates'] = {
                'defaults' => {
                  'per_page' => site_hash['paginate'].to_i,
                  'items' => 'posts'
                }
              }
              unless site_hash['paginate_path'].nil?
                overlay['templates']['defaults']['permalink'] = site_hash['paginate_path'].to_s
              end

              overlay
            end

            # Legacy migration path for v2 `autopages` into
            # `pagination.templates.generate`.
            def migrate_v2_autopages!(config, raw_autopages, compatibility_mode)
              return unless compatibility_mode == 'v2'

              autopages = Utils.safe_hash(raw_autopages)
              return if autopages.empty? || autopages['enabled'] == false

              migrated = []

              migrated.concat(migrate_v2_autopage_group(
                                raw_group: autopages['tags'],
                                index_key: 'tag',
                                items: 'all',
                                defaults: V2_AUTOPAGE_DEFAULTS['tags'],
                                split_delimiter: config.dig('syntax', 'split')
                              ))
              migrated.concat(migrate_v2_autopage_group(
                                raw_group: autopages['categories'],
                                index_key: 'category',
                                items: 'all',
                                defaults: V2_AUTOPAGE_DEFAULTS['categories'],
                                split_delimiter: config.dig('syntax', 'split')
                              ))
              migrated.concat(migrate_v2_autopage_group(
                                raw_group: autopages['collections'],
                                index_key: 'collection',
                                items: 'all',
                                defaults: V2_AUTOPAGE_DEFAULTS['collections'],
                                split_delimiter: config.dig('syntax', 'split')
                              ))

              return if migrated.empty?

              config['templates']['generate'].concat(migrated)
            end

            # Maps one v2 autopages group (tags/categories/collections) to one
            # generate definition.
            def migrate_v2_autopage_group(raw_group:, index_key:, items:, defaults:, split_delimiter:)
              group = Utils.safe_hash(raw_group)
              return [] if group.empty? || group['enabled'] == false

              layouts = Utils.normalise_layouts(group, split_delimiter: split_delimiter)
              layouts = [defaults['layout']] if layouts.empty?

              title = group['title']
              title = defaults['title'] unless present_config_value?(title)

              permalink = group['permalink']
              permalink = defaults['permalink'] unless present_config_value?(permalink)

              slugify = if group.key?('slugify')
                          Utils.safe_hash(group['slugify'])
                        else
                          Utils.deep_copy(defaults['slugify'])
                        end

              silent = boolean_config_value(group['silent'])

              [
                {
                  'items' => items,
                  'index' => index_key,
                  'layouts' => layouts,
                  'title' => title,
                  'permalink' => permalink,
                  'slugify' => slugify,
                  'silent' => silent
                }
              ]
            end

            # Indicates whether a config value should be treated as explicitly set.
            def present_config_value?(value)
              return false if value.nil?
              return false if value.is_a?(String) && value.strip.empty?
              return false if value.is_a?(Array) && value.empty?
              return false if value.is_a?(Hash) && value.empty?

              true
            end

            # Coerces loose truthy/falsey config values to a strict boolean.
            def boolean_config_value(value)
              return value if value == true || value == false

              value.to_s.strip.casecmp('true').zero?
            end
          end
        end
      end
    end
  end
end
