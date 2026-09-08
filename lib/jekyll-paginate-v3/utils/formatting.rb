# frozen_string_literal: true

module Jekyll
module Plugins
module PaginateV3

# Placeholder formatting helpers shared by pagination and template expansion.
module Utils

	# Resolves page-number placeholders through the shared placeholder pipeline.
	def self.format_page_number(pattern, current_page, max_pages = nil, slugifier: nil)
		values = {
			'num' => placeholder_value(current_page.to_i)
		}
		values['max'] = placeholder_value(max_pages.to_i) unless max_pages.nil?

		parsed_pattern = if pattern.is_a?(Support::PlaceholderTemplate)
							pattern
						else
							placeholder_template(
								pattern,
								allowed: %w[num max],
								context: 'pagination permalink'
							)
						end
		parsed_pattern.render(values, default_representation: :raw, slugifier: slugifier, unresolved: :error)
	end

	# Resolves title and page-number placeholders in one non-recursive pass.
	def self.format_page_title(pattern, title, current_page = nil, max_pages = nil, slugifier: nil)
		values = {
			'title' => placeholder_value(title),
			'num' => placeholder_value(current_page.to_i)
		}
		values['max'] = placeholder_value(max_pages.to_i) unless max_pages.nil?

		parsed_pattern = if pattern.is_a?(Support::PlaceholderTemplate)
							pattern
						else
							placeholder_template(
								pattern,
								allowed: %w[title num max],
								context: 'pagination title'
							)
						end
		parsed_pattern.render(values, default_representation: :raw, slugifier: slugifier, unresolved: :error)
	end

	# Compatibility wrapper for callers with one raw token map. Both supported
	# syntaxes still use the central parser and opaque value binding.
	def self.replace_tokens(template, token_map)
		token_source = token_map.is_a?(Hash) ? token_map : {}
		normalised_token_map = token_source.each_with_object({}) do |(raw_key, value), memo|
			key = raw_key.to_s
			next if key.empty?

			memo[key] = placeholder_value(value)
		end
		return template.to_s if normalised_token_map.empty?

		placeholder_template(
			template,
			allowed: normalised_token_map.keys,
			context: 'token replacement'
		).render(normalised_token_map, default_representation: :raw)
	end

	# Builds one parser instance for callers that need partial or structural
	# binding rather than an immediately rendered string.
	def self.placeholder_template(pattern, allowed:, context:, allowed_filters: nil, unknown: Support::PlaceholderTemplate::UNKNOWN_ERROR)
		Support::PlaceholderTemplate.parse(
			pattern,
			allowed: allowed,
			context: context,
			allowed_filters: allowed_filters,
			unknown: unknown
		)
	end

	# Wraps one scalar in the representation-aware placeholder value type.
	def self.placeholder_value(raw, slugified: nil, raw_available: true)
		Support::PlaceholderTemplate::Value.new(
			raw: raw,
			slugified: slugified,
			raw_available: raw_available
		)
	end
end

end
end
end
