# frozen_string_literal: true

module Jekyll
module Plugins
module PaginateV3
module Pagination

# Lightweight Liquid-facing object for paginator neighbour links.
#
# Exposed under `paginator.current`, `paginator.next`, `paginator.previous`,
# alias `paginator.prev`, plus `paginator.first` and `paginator.last`.
class IndexReference < ::Liquid::Drop
	attr_reader :num, :page

	# Stores one page number plus optional page/document object and
	# positional metadata within the full paginated set.
	def initialize(num:, page_object:, item_count:, start_item_index:, end_item_index:)
		@num = num.to_i
		@page = page_object
		@item_count = item_count.to_i
		@start_item_index = start_item_index
		@end_item_index = end_item_index
	end

	# Number of items paginated to this index.
	def count
		@item_count
	end

	# 1-based index of the first item on this index.
	def start
		@start_item_index
	end

	# Hash form used by specs and non-Liquid inspection.
	def to_h
		{
			'num' => num,
			'page' => page,
			'count' => count,
			'start' => start,
			'end' => @end_item_index
		}
	end

	# Handles `end` because it is a Ruby keyword and cannot be a method name.
	def liquid_method_missing(method_name)
		return @end_item_index if method_name.to_s == 'end'

		super
	end
end

end
end
end
end
