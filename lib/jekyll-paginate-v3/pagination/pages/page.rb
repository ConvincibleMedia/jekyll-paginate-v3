# frozen_string_literal: true

module Jekyll
module Plugins
module PaginateV3
module Pagination
module Pages

# In-memory index page generated from a pagination template for a
# specific page number.
#
# Used by Pagination::Model to emit page-based pagination output.
class Page < Jekyll::Page

	include PagerSupport

	# Clones template content/data and annotates it with pagination metadata.
	def initialize(template_item, current_page, total_pages, index_filename)
		@site = template_item.site
		@base = template_base_path(template_item)
		@dir = template_directory(template_item)
		@url = nil
		@name = index_filename.to_s.empty? ? 'index.html' : index_filename

		process(@name)

		# Each emitted page owns its mutable frontmatter containers so later hooks cannot alter sibling pages or their template.
		self.data = Utils.deep_copy(Utils.safe_hash(template_item.data))
		self.content = template_item.content
		self.data['pagination_info'] = {
			'curr_page' => current_page,
			'total_pages' => total_pages
		}
		self.ext = template_extname(template_item)
		self.data['path'] = template_path(template_item) if current_page == 1

		validate_data!(template_path(template_item))
		validate_permalink!(template_path(template_item))
	end

	private

	# Resolves a stable page base path for generated in-memory pages.
	def template_base_path(template_item)
		if template_item.is_a?(Jekyll::Page)
			return template_item.instance_variable_get(:@base).to_s
		end

		template_item.site.source.to_s
	end

	# Resolves one source directory-like value for generated page URLs.
	def template_directory(template_item)
		directory = if template_item.respond_to?(:dir)
									template_item.dir.to_s
								elsif template_item.respond_to?(:url)
									template_item.url.to_s
								else
									'/'
								end

		directory = '/' if directory.strip.empty?
		directory = "/#{directory}" unless directory.start_with?('/')
		directory.end_with?('/') ? directory : "#{directory}/"
	end

	# Resolves source extname from pages or documents.
	def template_extname(template_item)
		return template_item.extname.to_s if template_item.respond_to?(:extname)
		return template_item.ext.to_s if template_item.respond_to?(:ext)

		'.html'
	end

	# Resolves source path used by validators and compatibility metadata.
	def template_path(template_item)
		return template_item.path.to_s if template_item.respond_to?(:path)

		''
	end
end

end
end
end
end
end
