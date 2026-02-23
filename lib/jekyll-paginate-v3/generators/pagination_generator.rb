# frozen_string_literal: true

module Jekyll
  module Plugins
    module PaginateV3
      module Generators
        # Jekyll generator entry point for paginate-v3.
        #
        # Used by Jekyll's generator lifecycle to invoke the v3 pagination
        # pipeline for each site build.
        class PaginationGenerator < Jekyll::Generator
          safe true
          priority :lowest

          # Entrypoint called by Jekyll once the site graph is loaded.
          #
          # Normalises config, wires lightweight callbacks for mutating site
          # content, then delegates all pagination behaviour to Pagination::Model.
          def generate(site)
            config = Config::Normaliser.normalise_site_config(site.config)
            config = enable_implicit_v1_compatibility(config, site)

            logger = Utils::Logger.new(debug_enabled: config['debug'])
            logger.debug("Normalised config summary: enabled=#{config['enabled']} compatibility=#{config['compatibility'] || 'none'} items=#{config['items']} templates.location=#{config.dig('templates', 'location')} generate.count=#{config.dig('templates', 'generate')&.length || 0}.")

            unless config['enabled']
              logger.info('Disabled in site config.')
              return
            end

            # Shared logger callback so deeper layers do not depend directly on
            # Jekyll logger globals.
            log_lambda = logger.method(:call)

            # Abstract site mutation so the model can add pages or documents
            # without knowing where Jekyll stores each item type.
            add_item_lambda = lambda do |item|
              if item.respond_to?(:collection) && !item.collection.nil?
                site.collections[item.collection.label].docs << item
              else
                site.pages << item
              end
              item
            end

            # Mirror add_item_lambda for replacing template pages with generated
            # paginated siblings.
            remove_item_lambda = lambda do |item|
              if item.respond_to?(:collection) && !item.collection.nil?
                site.collections[item.collection.label].docs.delete_if { |doc| doc == item }
              else
                site.pages.delete_if { |page| page == item }
              end
            end

            model = Pagination::Model.new(
              site: site,
              site_config: config,
              log_lambda: log_lambda,
              add_item_lambda: add_item_lambda,
              remove_item_lambda: remove_item_lambda
            )

            processed_templates = model.run
            logger.info("Complete, processed #{processed_templates} pagination template(s)")
          end

          private

          # Convenience bridge for old jekyll-paginate sites that still define
          # `paginate`/`paginate_path` without explicit v3 config.
          def enable_implicit_v1_compatibility(config, site)
            return config unless config['compatibility'].nil?
            return config unless legacy_v1_site_config_present?(site)

            Jekyll.logger.warn('Pagination:', 'Detected legacy `paginate` config; enabling `compatibility: v1` automatically.')

            adjusted = Jekyll::Utils.deep_merge_hashes(site.config, {
              'pagination' => {
                'compatibility' => 'v1'
              }
            })

            Config::Normaliser.normalise_site_config(adjusted)
          end

          # Detects whether the site includes the legacy v1 top-level config key.
          def legacy_v1_site_config_present?(site)
            !site.config['paginate'].nil?
          end
        end
      end
    end
  end
end
