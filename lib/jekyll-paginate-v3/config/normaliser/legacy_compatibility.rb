# frozen_string_literal: true

module Jekyll
  module Plugins
    module PaginateV3
      module Config
        class Normaliser
          class << self
            private
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
