# frozen_string_literal: true

module Jekyll
module Plugins
module PaginateV3
module Query
class Filter
	# Filter-formatting helpers used for human-readable diagnostics.
	# Structure: filter trees are traversed and rendered into concise
	# textual expressions for logging and debugging output.

	private

	# Renders a normalised filter tree to readable text for diagnostics.
	def filter_to_s_internal(filter)
		join_mode = filter['join'] || 'or'

		include_fragments = filter['include'].map { |entry| filter_definition_to_s(entry) }
		include_text = include_fragments.empty? ? 'true' : include_fragments.join(" #{join_mode} ")

		exclude_fragments = filter['exclude'].map { |entry| filter_definition_to_s(entry) }
		return include_text if exclude_fragments.empty?

		exclude_text = exclude_fragments.join(" #{join_mode} ")
		"(#{include_text}) and not (#{exclude_text})"
	end

	# Renders one filter definition node.
	def filter_definition_to_s(definition)
		if group_definition?(definition)
			"(#{filter_to_s_internal(definition)})"
		elsif scalar_definition?(definition)
			split_text = definition['split'] == false ? 'split:false' : "split:'#{definition['split']}'"
			mode_text = definition['mode'] == 'first' ? "first:#{definition['first']}" : definition['mode']
			"match #{definition['match']} (#{mode_text}, #{split_text})"
		elsif range_definition?(definition)
			if definition.key?('min') && definition.key?('max')
				"#{definition['min']} to #{definition['max']} (#{definition['mode']})"
			elsif definition.key?('min')
				"#{definition['min']} or more (#{definition['mode']})"
			else
				"#{definition['max']} or less (#{definition['mode']})"
			end
		else
			'[invalid]'
		end
	end

	# Detects normalised group nodes.
	def group_definition?(definition)
		definition.is_a?(Hash) && definition.key?('include') && definition.key?('exclude') && definition.key?('join')
	end

	# Detects normalised scalar nodes.
	def scalar_definition?(definition)
		definition.is_a?(Hash) && definition.key?('match') && definition.key?('mode') && definition.key?('split')
	end

	# Detects normalised range nodes.
	def range_definition?(definition)
		definition.is_a?(Hash) && (definition.key?('min') || definition.key?('max'))
	end
end
end
end
end
end
