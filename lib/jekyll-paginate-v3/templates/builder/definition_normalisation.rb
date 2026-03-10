# frozen_string_literal: true

module Jekyll
module Plugins
module PaginateV3
module Templates

# Generated-template definition normalisation helpers for `Builder`.
# Structure: each generation definition is validated and canonicalised
# so downstream entry-building and template emission stay deterministic.
class Builder

	private

	def normalise_definition(raw_definition, default_collection)
		definition = Utils.safe_hash(raw_definition)
		return nil if definition.empty?
		silent = normalise_boolean(definition['silent'])

		unless present_config_value?(definition['items'])
			@log_lambda.call('Skipping generated index config with missing `items` key.', 'warn') unless silent
			return nil
		end

		index_keys = Utils.delimited_array(definition['index'], delimiter: @split_delimiter).map { |key| key.to_s.strip }.reject(&:empty?)
		unless index_keys.empty?
			duplicated_keys = index_keys.group_by { |key| key }.select { |_, values| values.length > 1 }.keys
			unless duplicated_keys.empty?
				raise ArgumentError, "Generated index config contains duplicate `index` key(s): #{duplicated_keys.join(', ')}."
			end
		end

		layouts = Utils.normalise_layouts(definition, split_delimiter: @split_delimiter)
		if layouts.empty?
			@log_lambda.call('Skipping generated index config with no `layout`/`layouts` value.', 'warn') unless silent
			return nil
		end

		filters = Utils.safe_hash(definition['filters'])
		if definition.key?('filter')
			index_keys.each { |key| filters[key] = definition['filter'] unless filters.key?(key) }
		end

		group_configuration = normalise_group_configuration(definition['group'], index_keys)

		{
			'items' => definition['items'],
			'index' => index_keys,
			'filters' => filters,
			'group_by_key' => group_configuration['group_by_key'],
			'group_fallback_by_key' => group_configuration['group_fallback_by_key'],
			'layouts' => layouts,
			'collection' => normalise_collection(definition['collection'], default_collection),
			'frontmatter' => Utils.safe_hash(definition['frontmatter']),
			'permalink' => definition['permalink'].to_s,
			'title' => definition['title'].to_s,
			'slugify' => normalise_slugify_config(definition['slugify']),
			'silent' => silent,
			'allow_empty' => normalise_boolean(definition['allow_empty']),
			'pagination_overrides' => extract_pagination_overrides(definition)
		}
	end

	# Splits non-special keys from a generate definition so they can be
	# merged into the generated template's pagination config.
	def extract_pagination_overrides(definition)
		overrides = Utils.safe_hash(definition).reject { |key, _| SPECIAL_KEYS.include?(key) }

		# `permalink` and `title` on generate definitions are page-level values
		# for generated templates, not paginator suffix patterns.
		overrides
	end

	# Purpose: Normalises collection targets into canonical form.
	# Connects to: the surrounding pagination flow in this file.
	# Params: `raw_collection`, `default_collection`.
	# Returns: a value consumed by the next pipeline step.
	def normalise_collection(raw_collection, default_collection)
		entries = Utils.delimited_array(raw_collection, delimiter: @split_delimiter)
		entries = Utils.deep_copy(default_collection) if entries.empty?
		if entries.length > 2
			raise ArgumentError, 'Generated index config `collection` may contain at most two values.'
		end

		entries = entries.map { |entry| normalise_collection_entry(entry) }.reject { |entry| entry.to_s.empty? }
		entries = Utils.deep_copy(default_collection) if entries.empty?
		entries
	end

	# Normalises one collection target and coerces template-relative keywords.
	def normalise_collection_entry(raw_entry)
		entry = raw_entry.to_s.strip
		return '' if entry.empty?

		pages_keyword = @site_config.dig('keywords', 'pages').to_s
		self_keyword = @site_config.dig('keywords', 'self').to_s
		shadow_keyword = @site_config.dig('keywords', 'shadow').to_s
		clone_keyword = @site_config.dig('keywords', 'clone').to_s

		return 'pages' if entry == pages_keyword || entry.casecmp('pages').zero?
		return 'pages' if entry == self_keyword || entry.casecmp('self').zero?
		return 'pages' if entry == shadow_keyword || entry.casecmp('shadow').zero?
		return 'pages' if entry == clone_keyword || entry.casecmp('clone').zero?

		entry
	end

	# Returns true when a config value should be treated as explicitly set.
	def present_config_value?(value)
		return false if value.nil?
		return false if value.is_a?(String) && value.strip.empty?
		return false if value.is_a?(Array) && value.empty?
		return false if value.is_a?(Hash) && value.empty?

		true
	end

	# Normalises generate-level grouped-index configuration.
	#
	# Rules:
	# - no `group` => no grouped levels
	# - single-key `index`: try unkeyed config first, with keyed fallback
	#   only for `{ <index_key>: ... }` hashes
	# - multi-key `index`: `group` must be a hash keyed by index keys
	def normalise_group_configuration(raw_group, index_keys)
		return { 'group_by_key' => {}, 'group_fallback_by_key' => {} } if raw_group == false
		return { 'group_by_key' => {}, 'group_fallback_by_key' => {} } unless present_config_value?(raw_group)

		if index_keys.empty?
			raise ArgumentError, '`group` cannot be used when `index` is not configured.'
		end

		if index_keys.length == 1
			key = index_keys.first
			group_by_key = { key => raw_group }
			fallback_by_key = {}

			if raw_group.is_a?(Hash)
				hash_group = Utils.safe_hash(raw_group)
				if hash_group.keys == [key] && hash_group[key] != false && present_config_value?(hash_group[key])
					fallback_by_key[key] = hash_group[key]
				end
			end

			return {
				'group_by_key' => group_by_key,
				'group_fallback_by_key' => fallback_by_key
			}
		end

		unless raw_group.is_a?(Hash)
			raise ArgumentError, 'Multi-level `index` requires `group` to be keyed by index frontmatter key.'
		end

		hash_group = Utils.safe_hash(raw_group)
		invalid_keys = hash_group.keys - index_keys
		unless invalid_keys.empty?
			raise ArgumentError, "Grouped config key(s) are not present in `index`: #{invalid_keys.join(', ')}."
		end

		group_by_key = {}
		index_keys.each do |key|
			next unless hash_group.key?(key)
			next if hash_group[key] == false
			next unless present_config_value?(hash_group[key])

			group_by_key[key] = hash_group[key]
		end

		if group_by_key.empty?
			raise ArgumentError, 'Multi-level `group` must define at least one indexed frontmatter key.'
		end

		{
			'group_by_key' => group_by_key,
			'group_fallback_by_key' => {}
		}
	end

	# Resolves default generated-template collection targets from site defaults.
	#
	# `self`, `shadow`, and `clone` are template-relative modes and therefore
	# become `pages` during template generation.
	def default_generation_collection
		raw_collection = @site_config.dig('templates', 'collection')
		entries = Utils.arrayify(raw_collection).map { |entry| entry.to_s.strip }.reject(&:empty?)
		entries = ['pages'] if entries.empty?
		if entries.length > 2
			raise ArgumentError, 'pagination.collection may contain at most two values.'
		end

		entries.map { |entry| normalise_collection_entry(entry) }
	end

	# Builds one concise debug label for configured index keys.
	def describe_index_keys(index_keys)
		keys = Utils.arrayify(index_keys).map { |key| key.to_s.strip }.reject(&:empty?)
		return '(none)' if keys.empty?

		keys.join(', ')
	end
end

end
end
end
end
