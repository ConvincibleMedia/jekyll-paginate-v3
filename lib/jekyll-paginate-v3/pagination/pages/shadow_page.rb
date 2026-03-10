# frozen_string_literal: true

module Jekyll
module Plugins
module PaginateV3
module Pagination
module Pages

# In-memory index page that behaves like a page while exposing collection
# metadata for compatibility checks.
#
# Used by Pagination::Model when emitting `collection: shadow` indexes.
class ShadowPage < Page

	attr_reader :collection

	# Mirrors `Page` generation but publishes collection metadata without
	# becoming a true collection document.
	def initialize(template_item, current_page, total_pages, index_filename, collection:)
		super(template_item, current_page, total_pages, index_filename)
		@collection = collection
		return if @collection.nil?

		self.data['collection'] = @collection.label.to_s
	end
end

end
end
end
end
end
