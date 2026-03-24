# frozen_string_literal: true

require 'digest'

module Jekyll
module Plugins
module PaginateV3
module Templates

# Generated pagination template document for collection-based template
# locations.
#
# Used by Templates::Builder for generated collection-document
# templates.
class DocumentTemplate < Jekyll::Document
	alias_method :ext, :extname

	# Creates an in-memory collection document seeded from frontmatter and
	# content supplied by generate config.
	def initialize(site:, collection:, pagination_config:, frontmatter:, content:, generated_metadata:)
		virtual_path = build_virtual_path(site, collection, pagination_config, frontmatter)
		generated_metadata_hash = Utils.safe_hash(generated_metadata)

		initialise_document(site, collection, virtual_path)

		merge_data!(Utils.safe_hash(frontmatter))
		self.content = content.to_s
		self.data['pagination'] = Utils.safe_hash(pagination_config)
		self.data['pagination']['template'] = true
		self.data['paginate_v3'] = generated_metadata_hash

		apply_v2_compatibility_metadata!

		trigger_hooks(:post_init)
	end

	private

	# Builds a deterministic synthetic source path inside destination
	# collection.
	def build_virtual_path(site, collection, pagination_config, frontmatter)
		signature = [collection.label, pagination_config, frontmatter].inspect
		filename = "_paginate_v3_generated_#{Digest::MD5.hexdigest(signature)}.md"
		File.join(site.source, collection.relative_directory, filename)
	end

	# Adds legacy-friendly fields only when v2 compatibility is active.
	def apply_v2_compatibility_metadata!
		return unless data.dig('paginate_v3', 'compatibility') == 'v2'

		autopage_data = Utils.safe_hash(data.dig('paginate_v3', 'autopages'))
		return if autopage_data.empty?

		data['autopages'] = autopage_data
		key = autopage_data['key'].to_s
		return if key.empty?
		return if key == 'collection'
		return if key.include?('.') || key.include?(':')

		data[key] = autopage_data['value']
	end

	# Initialises minimal Jekyll::Document state for a synthetic doc.
	def initialise_document(site, collection, path)
		@site = site
		@path = path
		@collection = collection
		@type = @collection.label.to_sym
		@has_yaml_header = nil
		@extname = '.md'

		if draft?
			categories_from_path('_drafts')
		else
			categories_from_path(collection.relative_directory)
		end

		data.default_proc = proc do |_, key|
			site.frontmatter_defaults.find(relative_path, type, key)
		end
	end
end

end
end
end
end
