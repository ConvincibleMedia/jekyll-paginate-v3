# frozen_string_literal: true

require 'digest'

module Jekyll
module Plugins
module PaginateV3
module Templates

# Generated pagination template page backed by in-memory frontmatter and
# content.
#
# Used by Templates::Builder for generated page-based templates.
class PageTemplate < Jekyll::Page
	# Creates an in-memory page that behaves like a hand-authored
	# pagination template.
	def initialize(site:, pagination_config:, frontmatter:, content:, generated_metadata:)
		@site = site
		@base = site.source
		@dir = '/'
		@name = 'index.html'
		@url = '/'
		@path = build_virtual_path(site, pagination_config, frontmatter)

		process(@name)

		generated_metadata_hash = Utils.safe_hash(generated_metadata)
		self.data = Utils.safe_hash(frontmatter)
		self.content = content.to_s
		self.data['pagination'] = Utils.safe_hash(pagination_config)
		self.data['pagination']['template'] = true
		self.data['paginate_v3'] = generated_metadata_hash

		apply_v2_compatibility_metadata!
		apply_permalink!

		data.default_proc = proc do |_, key|
			site.frontmatter_defaults.find(relative_path, type, key)
		end
	end

	private

	# Builds a deterministic virtual source path for this synthetic page.
	def build_virtual_path(site, pagination_config, frontmatter)
		signature = [pagination_config, frontmatter].inspect
		File.join(site.source, "_paginate_v3_generated_#{Digest::MD5.hexdigest(signature)}.md")
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

	# Applies frontmatter permalink directly so the synthetic template
	# lands at the intended route before pagination expansion.
	def apply_permalink!
		return unless data['permalink']

		permalink = data['permalink'].to_s
		@dir = permalink
		@url = Utils.ensure_full_path(permalink, 'index', '.html')
	end
end

end
end
end
end
