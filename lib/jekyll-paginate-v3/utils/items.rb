# frozen_string_literal: true

module Jekyll
  module Plugins
    module PaginateV3
      module Utils
        # Item-level helpers for pagination and template discovery.
        #
        # Used by Pagination::Model and related runtime components.

        # Calculates page count for a list and per-page size.
        def self.calculate_number_of_pages(items, per_page)
          page_size = [per_page.to_i, 1].max
          (items.size.to_f / page_size).ceil
        end

        # Returns true when the object appears to be a generated index page.
        def self.generated_index?(item)
          return false unless item.respond_to?(:data)
          return false unless item.data.is_a?(Hash)

          return true if item.data.dig('pagination', 'generated') && item.data.dig('pagination', 'index')

          %w[jekyll-paginate-v2 jekyll-paginate-v3].include?(item.data['autogen'])
        end

        # Returns true when the object looks like a pagination template.
        def self.pagination_template?(item)
          return false unless item.respond_to?(:data)
          return false unless item.data.is_a?(Hash)

          item.data['pagination'].is_a?(Hash)
        end

        # Safe relative path for pages and documents.
        def self.relative_item_path(item)
          if item.respond_to?(:cleaned_relative_path)
            ext = item.respond_to?(:extname) ? item.extname.to_s : ''
            remove_leading_slash("#{item.cleaned_relative_path}#{ext}")
          elsif item.respond_to?(:relative_path)
            remove_leading_slash(item.relative_path.to_s)
          elsif item.respond_to?(:path)
            remove_leading_slash(item.path.to_s)
          else
            ''
          end
        end

        # Collection label helper that treats pages as nil collection.
        def self.item_collection_label(item)
          return nil unless item.respond_to?(:collection)
          return nil if item.collection.nil?

          item.collection.respond_to?(:label) ? item.collection.label.to_s : nil
        end
      end
    end
  end
end
