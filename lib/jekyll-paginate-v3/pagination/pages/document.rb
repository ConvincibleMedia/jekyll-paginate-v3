# frozen_string_literal: true

require 'digest'

module Jekyll
module Plugins
module PaginateV3
module Pagination
module Pages

# In-memory index document generated from a pagination template for a
# specific page number.
#
# Used by Pagination::Model when paginating collection documents.
class Document < Jekyll::Document

	attr_accessor :pager
	
	alias_method :ext, :extname

	# Clones a collection template document for one concrete page number.
	def initialize(template_item, current_page, total_pages, _index_filename, collection:)
		target_collection = collection
		source_path = template_path(template_item)
		virtual_path = build_virtual_path(template_item.site, target_collection, source_path, current_page)

		initialise_document(template_item.site, target_collection, virtual_path)

		merge_data!(template_item.data)
		self.content = template_item.content
		self.data['pagination_info'] = {
			'curr_page' => current_page,
			'total_pages' => total_pages
		}
		@extname = template_extname(template_item)
		self.data['path'] = source_path if current_page == 1 && !source_path.empty?

		trigger_hooks(:post_init)
	end

	private

	# Builds a deterministic synthetic source path inside destination collection.
	def build_virtual_path(site, collection, source_path, current_page)
		signature = [source_path, collection.label, current_page].join(':')
		filename = "_paginate_v3_#{Digest::MD5.hexdigest(signature)}.md"
		File.join(site.source, collection.relative_directory, filename)
	end

	# Resolves source path for compatibility metadata.
	def template_path(template_item)
		return template_item.path.to_s if template_item.respond_to?(:path)

		''
	end

	# Resolves source extname from pages or documents.
	def template_extname(template_item)
		return template_item.extname.to_s if template_item.respond_to?(:extname)
		return template_item.ext.to_s if template_item.respond_to?(:ext)

		'.html'
	end

	# Initialises minimal document internals required by Jekyll renderers.
	def initialise_document(site, collection, path)
		@site = site
		@path = path
		@collection = collection
		@type = @collection.label.to_sym
		@has_yaml_header = nil

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
end
