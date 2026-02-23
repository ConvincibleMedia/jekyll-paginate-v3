# frozen_string_literal: true

module Jekyll
  module Plugins
    module PaginateV3
      module Pagination
        module Pages
          # In-memory index document generated from a pagination template for a
          # specific page number.
          #
          # Used by Pagination::Model when paginating collection documents.
          class Document < Jekyll::Document
            attr_accessor :pager
            alias_method :ext, :extname

            # Clones a collection template document for one concrete page number.
            def initialize(template_document, current_page, total_pages, _index_filename)
              initialise_document(template_document.site, template_document.collection, template_document.path)

              merge_data!(template_document.data)
              self.content = template_document.content
              self.data['pagination_info'] = {
                'curr_page' => current_page,
                'total_pages' => total_pages
              }
              @extname = template_document.extname
              self.data['path'] = template_document.path if current_page == 1

              trigger_hooks(:post_init)
            end

            # Sets an explicit output URL for the synthetic document.
            def set_url(url_value)
              @url = url_value
            end

            private

            # Initialises minimal document internals required by Jekyll renderers.
            def initialise_document(site, collection, path)
              @site = site
              @path = path
              @collection = collection
              @type = @collection.label.to_sym
              @has_yaml_header = nil

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
end
