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

	attr_reader :key, :current, :next, :previous, :first, :last

	# Stores one complete set of group neighbour references.
	#
	# Use `previous_reference` going forward; `prev_reference` remains as
	# a backwards-compatible alias.
	def initialize(key:, current:, next_reference:, first_reference:, last_reference:, previous_reference: nil, prev_reference: nil)
		@key = key.to_s
		@current = current
		@next = next_reference
		@previous = previous_reference.nil? ? prev_reference : previous_reference
		@first = first_reference
		@last = last_reference
	end

	# Backwards-compatible alias for previous grouped-set reference.
	def prev
		previous
	end

	# Hash form used by specs and non-Liquid inspection.
	def to_h
		{
			'key' => key,
			'current' => current,
			'next' => self.next,
			'previous' => previous,
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
