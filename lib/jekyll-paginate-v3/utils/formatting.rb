# frozen_string_literal: true

module Jekyll
module Plugins
module PaginateV3
module Utils
	# Token and placeholder formatting helpers.
	#
	# Used by paginator and generated-index code to substitute placeholders
	# in URLs and page titles.

	# Replaces `:num` and optionally `:max` placeholders.
	def self.format_page_number(pattern, current_page, max_pages = nil)
		output = pattern.to_s.sub(':num', current_page.to_i.to_s)
		output = output.sub(':max', max_pages.to_i.to_s) unless max_pages.nil?
		output
	end

	# Replaces `:title` and numeric placeholders in title patterns.
	def self.format_page_title(pattern, title, current_page = nil, max_pages = nil)
		format_page_number(pattern.to_s.sub(':title', title.to_s), current_page, max_pages)
	end

	# Replaces placeholders in a string where keys are in `token_map`.
	#
	# Replacement is done in one pass using a longest-key-first matcher so
	# overlapping placeholders stay deterministic, for example `:foob`
	# always wins over `:foo` in `:foobar`.
	def self.replace_tokens(template, token_map)
		output = template.to_s
		token_source = token_map.is_a?(Hash) ? token_map : {}
		normalised_token_map = token_source.each_with_object({}) do |(raw_key, value), memo|
			key = raw_key.to_s
			next if key.empty?

			memo[key] = value.to_s
		end
		return output if normalised_token_map.empty?

		sorted_keys = normalised_token_map.keys.sort_by { |key| [-key.length, key] }
		token_pattern = /:(#{sorted_keys.map { |key| Regexp.escape(key) }.join('|')})/

		output.gsub(token_pattern) do
			normalised_token_map[Regexp.last_match(1)]
		end
	end
end
end
end
end
