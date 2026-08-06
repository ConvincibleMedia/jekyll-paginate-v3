# frozen_string_literal: true

module Jekyll
module Plugins
module PaginateV3
module Templates

# Generated-template definition normalisation helpers for `Builder`.
# Structure: each generate definition is reduced to:
# - `pagination` config copied onto the generated template
# - generate-only controls for template object creation (`frontmatter`
#   and `content`).
class Builder

	private

	def normalise_definition(raw_definition, default_collection)
		definition = Utils.safe_hash(raw_definition)
		return nil if definition.empty?

		pagination_config = Utils.safe_hash(definition).reject { |key, _| SPECIAL_KEYS.include?(key) }
		template_collection = normalise_collection(pagination_config['collection'], default_collection)

		{
			'pagination' => pagination_config,
			'template_collection' => template_collection,
			'frontmatter' => Utils.safe_hash(definition['frontmatter']),
			'content' => definition.key?('content') ? definition['content'].to_s : ''
		}
	end

	# Purpose: Normalises collection targets into canonical form.
	# Connects to: the surrounding pagination flow in this file.
	# Params: `raw_collection`, `default_collection`.
	# Returns: a value consumed by the next pipeline step.
	def normalise_collection(raw_collection, default_collection)
		entries = Utils.delimited_array(raw_collection, delimiter: @split_delimiter)
		entries = Utils.deep_copy(default_collection) if entries.empty?
		if entries.length > 2
			raise ArgumentError, 'Generated template `collection` may contain at most two values.'
		end

		entries = entries.map { |entry| normalise_collection_entry(entry) }.reject { |entry| entry.to_s.empty? }
		entries = Utils.deep_copy(default_collection) if entries.empty?
		entries
	end

	# Normalises one generated-template collection target. Generated templates
	# have no source collection, so all collection-mode keywords become pages.
	def normalise_collection_entry(raw_entry)
		entry = raw_entry.to_s.strip
		return '' if entry.empty?

		return Config::COLLECTION_TARGET_PAGES if Config::COLLECTION_TARGET_BY_KEY.value?(entry)

		Config::COLLECTION_TARGET_BY_KEY.each do |key, _internal_target|
			return Config::COLLECTION_TARGET_PAGES if entry == @site_config.dig('keywords', key).to_s
		end

		entry
	end

	# Resolves default generated-template collection targets from site defaults.
	#
	# Template-relative modes become the internal pages target during template
	# generation because a generated template has no source collection.
	def default_generation_collection
		raw_collection = @site_config['collection']
		entries = Utils.arrayify(raw_collection).map { |entry| entry.to_s.strip }.reject(&:empty?)
		entries = [Config::COLLECTION_TARGET_PAGES] if entries.empty?
		if entries.length > 2
			raise ArgumentError, 'pagination.collection may contain at most two values.'
		end

		entries.map { |entry| normalise_collection_entry(entry) }
	end
end

end
end
end
end
