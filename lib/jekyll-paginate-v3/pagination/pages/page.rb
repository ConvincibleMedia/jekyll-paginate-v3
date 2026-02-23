# frozen_string_literal: true

module Jekyll
  module Plugins
    module PaginateV3
      module Pagination
        module Pages
          # In-memory index page generated from a pagination template for a
          # specific page number.
          #
          # Used by Pagination::Model to emit page-based pagination output.
          class Page < Jekyll::Page
            attr_accessor :pager

            # Clones template content/data and annotates it with pagination metadata.
            def initialize(template_page, current_page, total_pages, index_filename)
              @site = template_page.site
              @base = ''
              @url = ''
              @name = index_filename.to_s.empty? ? 'index.html' : index_filename

              process(@name)

              self.data = Jekyll::Utils.deep_merge_hashes(template_page.data, {})
              self.content = template_page.content
              self.data['pagination_info'] = {
                'curr_page' => current_page,
                'total_pages' => total_pages
              }
              self.ext = template_page.extname
              self.data['path'] = template_page.path if current_page == 1

              validate_data!(template_page.path)
              validate_permalink!(template_page.path)
            end

            # Sets an explicit output URL for the synthetic page.
            def set_url(url_value)
              @url = url_value
            end
          end
        end
      end
    end
  end
end
