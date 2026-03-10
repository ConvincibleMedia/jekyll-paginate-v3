# frozen_string_literal: true

module Jekyll
module Plugins
module PaginateV3
module Templates

# Generated pagination template page built from a layout file and
# generated frontmatter. The pagination model later expands this
# template into index pages.
#
# Used by Templates::Builder for generated page-based templates.
class PageTemplate < Jekyll::Page
	# Creates an in-memory page that behaves like a hand-authored
	# pagination template.
	def initialize(site:, layout_name:, pagination_config:, frontmatter:, generated_metadata:)
		@site = site
		@base = site.source
		@name = 'index.html'

		@path = resolve_layout_path(site, layout_name)

		process(@name)
		read_yaml(File.dirname(@path), File.basename(@path))

		layout_data = Jekyll::Utils.deep_merge_hashes(self.data, {})
		generated_metadata_hash = Utils.safe_hash(generated_metadata)
		self.data = Jekyll::Utils.deep_merge_hashes(frontmatter, layout_data)
		self.data['layout'] = File.basename(layout_name, File.extname(layout_name))
		self.data['pagination'] = Utils.merge_generated_template_pagination(
			pagination_config,
			layout_data['pagination'],
			generated_metadata_hash['compatibility']
		)
		self.data['pagination']['template'] = true
		self.data['paginate_v3'] = generated_metadata_hash

		apply_v2_compatibility_metadata!

		apply_permalink!

		data.default_proc = proc do |_, key|
			site.frontmatter_defaults.find(File.join('_layouts', layout_name), type, key)
		end
	end

	private

	# Resolves layout path from theme first, then site source.
	def resolve_layout_path(site, layout_name)
		layout_dir = '_layouts'
		path = if site.in_theme_dir(site.source) == site.source
							site.in_theme_dir(site.source, layout_dir, layout_name)
						else
							site.in_source_dir(site.source, layout_dir, layout_name)
						end

		unless File.exist?(path)
			raise ArgumentError, "Layout '#{path}' does not exist"
		end

		path
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
