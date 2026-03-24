# frozen_string_literal: true

module Jekyll
module Plugins
module PaginateV3
module Pagination

# Liquid-facing trail object used by `paginator.trail`.
#
# Extends IndexReference with current-page markers and relative distance.
class TrailReference < IndexReference
	attr_reader :current, :distance

	# Stores trail metadata for one visible trail index entry.
	def initialize(num:, page_object:, item_count:, start_item_index:, end_item_index:, current:, distance:)
		super(
			num: num,
			page_object: page_object,
			item_count: item_count,
			start_item_index: start_item_index,
			end_item_index: end_item_index
		)
		@current = !!current
		@distance = distance.to_i
	end

	# Hash form used by specs and non-Liquid inspection.
	def to_h
		super.merge(
			'current' => current,
			'distance' => distance
		)
	end
end

end
end
end
end
