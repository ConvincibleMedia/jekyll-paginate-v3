# frozen_string_literal: true

module Jekyll
module Plugins
module PaginateV3

# Item-level helpers for pagination and template discovery.
#
# Used by Pagination::Model and related runtime components.
module Utils

	# Calculates page count for a list and one per-page definition.
	#
	# `per_page` can be either:
	# - Integer: fixed page size.
	# - Array: nth entry is used for page n, with the final entry reused.
	def self.calculate_number_of_pages(items, per_page)
		build_pagination_windows(items.size, per_page).length
	end

	# Normalises a per-page definition into an integer array.
	#
	# Invalid or non-positive entries are coerced to `1` so pagination
	# remains valid and cannot produce zero-sized pages.
	def self.normalise_per_page_pattern(per_page)
		raw_entries = per_page.is_a?(Array) ? per_page.flatten.compact : [per_page]
		pattern = raw_entries.map { |entry| [entry.to_i, 1].max }

		pattern.empty? ? [1] : pattern
	end

	# Resolves configured page size for one 1-based page number.
	#
	# When the page number exceeds the per-page pattern length, the final
	# pattern entry is reused indefinitely.
	def self.page_size_for_number(per_page, page_number)
		pattern = normalise_per_page_pattern(per_page)
		index = [page_number.to_i - 1, pattern.length - 1].min
		index = 0 if index.negative?

		pattern[index]
	end

	# Builds page windows for a total item count and per-page definition.
	#
	# Each returned window has:
	# - `num`: page number
	# - `page_size`: configured capacity for this page
	# - `count`: actual number of items on this page
	# - `offset_start` / `offset_end`: zero-based slice bounds
	# - `start` / `end`: 1-based item positions (or nil when empty)
	def self.build_pagination_windows(total_items, per_page)
		safe_total_items = [total_items.to_i, 0].max

		if safe_total_items.zero?
			first_page_size = page_size_for_number(per_page, 1)
			return [
				{
					'num' => 1,
					'page_size' => first_page_size,
					'count' => 0,
					'offset_start' => 0,
					'offset_end' => 0,
					'start' => nil,
					'end' => nil
				}
			]
		end

		windows = []
		page_number = 1
		offset = 0

		while offset < safe_total_items
			page_size = page_size_for_number(per_page, page_number)
			count = [page_size, safe_total_items - offset].min
			start_item_index = offset + 1
			end_item_index = offset + count

			windows << {
				'num' => page_number,
				'page_size' => page_size,
				'count' => count,
				'offset_start' => offset,
				'offset_end' => offset + count,
				'start' => start_item_index,
				'end' => end_item_index
			}

			offset += count
			page_number += 1
		end

		windows
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
