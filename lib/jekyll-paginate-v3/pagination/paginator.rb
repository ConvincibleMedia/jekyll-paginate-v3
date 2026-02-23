# frozen_string_literal: true

module Jekyll
  module Plugins
    module PaginateV3
      module Pagination
        # Exposes pagination metadata to Liquid as `paginator`.
        #
        # Used by Pagination::Model for every generated page/document.
        class Paginator
          attr_reader :page, :per_page, :items, :total_items, :total_pages,
                      :previous_page, :previous_page_path, :next_page, :next_page_path,
                      :page_path, :page_trail, :first_page, :first_page_path,
                      :last_page, :last_page_path

          def initialize(per_page:, first_page_url:, paginated_page_url:, items:, current_page:, total_pages:, index_name:, extension:, item_keyword:)
            @page = current_page
            @per_page = [per_page.to_i, 1].max
            @total_pages = [total_pages.to_i, 1].max
            @item_keyword = item_keyword.to_s.strip
            @item_keyword = 'items' if @item_keyword.empty?

            if @page > @total_pages
              raise ArgumentError, "page number cannot be greater than total pages (#{@page} > #{@total_pages})"
            end

            start_offset = (@page - 1) * @per_page
            end_offset = [start_offset + @per_page - 1, items.size - 1].min

            first_page_full = Utils.ensure_full_path(first_page_url, index_name, extension)
            paginated_full = Utils.ensure_full_path(paginated_page_url, index_name, extension)

            @total_items = items.size
            @items = items[start_offset..end_offset] || []
            @page_path = Utils.format_page_number(page_template(@page, first_page_full, paginated_full), @page, @total_pages)

            @previous_page = @page > 1 ? @page - 1 : nil
            @previous_page_path = if @previous_page.nil?
                                    nil
                                  elsif @previous_page == 1
                                    Utils.format_page_number(first_page_full, 1, @total_pages)
                                  else
                                    Utils.format_page_number(paginated_full, @previous_page, @total_pages)
                                  end

            @next_page = @page < @total_pages ? @page + 1 : nil
            @next_page_path = @next_page.nil? ? nil : Utils.format_page_number(paginated_full, @next_page, @total_pages)

            @first_page = 1
            @first_page_path = Utils.format_page_number(first_page_full, 1, @total_pages)
            @last_page = @total_pages
            @last_page_path = Utils.format_page_number(paginated_full, @last_page, @total_pages)
            @page_trail = nil
          end

          def page_trail=(trail)
            @page_trail = trail
          end

          # Converts the paginator payload into a Liquid-safe hash.
          #
          # v3 always exposes `items` and `total_items`; compatibility aliases can
          # be provided by changing `pagination.keywords.items`.
          def to_liquid
            payload = {
              'per_page' => per_page,
              'items' => items,
              'total_items' => total_items,
              'total_pages' => total_pages,
              'page' => page,
              'page_path' => page_path,
              'previous_page' => previous_page,
              'previous_page_path' => previous_page_path,
              'next_page' => next_page,
              'next_page_path' => next_page_path,
              'first_page' => first_page,
              'first_page_path' => first_page_path,
              'last_page' => last_page,
              'last_page_path' => last_page_path,
              'page_trail' => page_trail
            }

            payload[@item_keyword] = items
            payload["total_#{@item_keyword}"] = total_items

            payload
          end

          private

          def page_template(page_number, first_page_full, paginated_full)
            page_number == 1 ? first_page_full : paginated_full
          end
        end

        # Small Liquid-facing object used in pager trails.
        #
        # Used by Paginator page trail output.
        class PageTrail
          attr_reader :num, :path, :title

          def initialize(num, path, title)
            @num = num
            @path = path
            @title = title
          end

          def to_liquid
            {
              'num' => num,
              'path' => path,
              'title' => title
            }
          end
        end
      end
    end
  end
end
