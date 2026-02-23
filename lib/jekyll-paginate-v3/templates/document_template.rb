# frozen_string_literal: true

require 'yaml'
require 'digest'

module Jekyll
  module Plugins
    module PaginateV3
      module Templates
        # Generated pagination template document for collection-based template
        # locations.
        #
        # Used by Templates::Builder for generated collection-document
        # templates.
        class DocumentTemplate < Jekyll::Document
          alias_method :ext, :extname

          # Creates an in-memory collection document seeded from a layout file.
          def initialize(site:, collection:, layout_name:, pagination_config:, frontmatter:, generated_metadata:)
            layout_path = resolve_layout_path(site, layout_name)
            parsed_layout = parse_layout(layout_path)
            token_signature = Utils.safe_hash(generated_metadata['tokens']).sort.to_h.to_s
            virtual_path = File.join(site.source, collection.relative_directory, "_paginate_v3_#{Digest::MD5.hexdigest([layout_name, token_signature].join(':'))}.md")

            initialise_document(site, collection, virtual_path)

            merge_data!(parsed_layout['data'])
            merge_data!(frontmatter)
            self.content = parsed_layout['content']
            self.data['layout'] = File.basename(layout_name, File.extname(layout_name))
            self.data['pagination'] = Jekyll::Utils.deep_merge_hashes(pagination_config, Utils.safe_hash(parsed_layout['data']['pagination']))
            self.data['pagination']['template'] = true
            self.data['paginate_v3'] = Utils.safe_hash(generated_metadata)

            apply_v2_compatibility_metadata!

            trigger_hooks(:post_init)
          end

          private

          # Adds legacy-friendly fields only when v2 compatibility is active.
          def apply_v2_compatibility_metadata!
            return unless data.dig('paginate_v3', 'compatibility') == 'v2'

            autopage_data = Utils.safe_hash(data.dig('paginate_v3', 'autopages'))
            return if autopage_data.empty?

            data['autopages'] = autopage_data
            key = autopage_data['key'].to_s
            return if key.empty?
            return if key == 'collection'
            return if key.include?('.') || key.include?(':')

            data[key] = autopage_data['value']
          end

          # Resolves layout path from theme first, then site source.
          def resolve_layout_path(site, layout_name)
            layout_dir = '_layouts'
            if site.in_theme_dir(site.source) == site.source
              site.in_theme_dir(site.source, layout_dir, layout_name)
            else
              site.in_source_dir(site.source, layout_dir, layout_name)
            end
          end

          # Parses layout frontmatter/body so generated documents can inherit
          # defaults from the selected layout.
          def parse_layout(layout_path)
            unless File.exist?(layout_path)
              raise ArgumentError, "Layout '#{layout_path}' does not exist"
            end

            source = File.read(layout_path)
            frontmatter = {}
            body = source

            if source =~ /\A---\s*\n(.*?)\n---\s*\n/m
              raw_frontmatter = Regexp.last_match(1)
              frontmatter = YAML.safe_load(raw_frontmatter, aliases: true) || {}
              body = source.sub(/\A---\s*\n(.*?)\n---\s*\n/m, '')
            end

            {
              'data' => Utils.safe_hash(frontmatter),
              'content' => body
            }
          end

          # Initialises minimal Jekyll::Document state for a synthetic doc.
          def initialise_document(site, collection, path)
            @site = site
            @path = path
            @collection = collection
            @type = @collection.label.to_sym
            @has_yaml_header = nil
            @extname = '.md'

            if draft?
              categories_from_path('_drafts')
            else
              categories_from_path(collection.relative_directory)
            end

            data.default_proc = proc do |_, key|
              site.frontmatter_defaults.find(relative_path, type, key)
            end
          end
        end
      end
    end
  end
end
