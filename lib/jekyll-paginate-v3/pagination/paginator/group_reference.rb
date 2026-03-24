# frozen_string_literal: true

module Jekyll
module Plugins
module PaginateV3
module Pagination

# Liquid-facing grouped-set reference.
#
# Similar to IndexReference, but `start`/`end` represent group range
# bounds rather than 1-based item positions.
class GroupReference < ::Liquid::Drop
	
	attr_reader :num, :page, :count, :start

	# Stores one grouped-set neighbour reference.
	def initialize(num:, page_object:, item_count:, range_start:, range_end:)
		@num = num.to_i
		@page = page_object
		@count = item_count.to_i
		@start = range_start
		@range_end = range_end
	end

	# Hash form used by specs and non-Liquid inspection.
	def to_h
		payload = {
			'num' => num,
			'page' => page,
			'count' => count,
			'start' => start
		}
		payload['end'] = @range_end unless @range_end.nil?
		payload
	end

	# Handles `end` because it is a Ruby keyword and cannot be a method name.
	def liquid_method_missing(method_name)
		return @range_end if method_name.to_s == 'end'

		super
	end
end

end
end
end
end
