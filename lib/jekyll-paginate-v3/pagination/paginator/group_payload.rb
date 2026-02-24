# frozen_string_literal: true

module Jekyll
module Plugins
module PaginateV3
module Pagination

# Liquid-facing grouped-set payload for generated grouped indexes.
#
# Exposed in `paginator.groups` and by shortcut at `paginator.group`
# (deepest index level).
class GroupPayload < ::Liquid::Drop

	attr_reader :key, :current, :next, :prev, :first, :last

	# Stores one complete set of group neighbour references.
	def initialize(key:, current:, next_reference:, prev_reference:, first_reference:, last_reference:)
		@key = key.to_s
		@current = current
		@next = next_reference
		@prev = prev_reference
		@first = first_reference
		@last = last_reference
	end

	# Hash form used by specs and non-Liquid inspection.
	def to_h
		{
			'key' => key,
			'current' => current,
			'next' => self.next,
			'prev' => prev,
			'first' => first,
			'last' => last
		}
	end
end

end
end
end
end
