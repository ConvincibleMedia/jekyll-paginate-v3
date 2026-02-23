# frozen_string_literal: true

require 'jekyll'
require 'jekyll-paginate-v3/version'
require 'jekyll-paginate-v3/config/defaults'
require 'jekyll-paginate-v3/config/normaliser'
require 'jekyll-paginate-v3/utils/core'
require 'jekyll-paginate-v3/utils/logger'
require 'jekyll-paginate-v3/utils/paths'
require 'jekyll-paginate-v3/utils/formatting'
require 'jekyll-paginate-v3/utils/nested_data'
require 'jekyll-paginate-v3/utils/items'
require 'jekyll-paginate-v3/query/parser'
require 'jekyll-paginate-v3/query/filter'
require 'jekyll-paginate-v3/query/sorter'
require 'jekyll-paginate-v3/pagination/paginator'
require 'jekyll-paginate-v3/pagination/pages/page'
require 'jekyll-paginate-v3/pagination/pages/document'
require 'jekyll-paginate-v3/templates/page_template'
require 'jekyll-paginate-v3/templates/document_template'
require 'jekyll-paginate-v3/templates/builder'
require 'jekyll-paginate-v3/pagination/model'
require 'jekyll-paginate-v3/generators/pagination_generator'

module Jekyll
  module Plugins
    # Namespace anchor for all paginate-v3 runtime components.
    #
    # Used by Jekyll plugin loading as the root module for config normalisation,
    # query/filtering, generated template building, and paginated index emission.
    module PaginateV3
    end
  end
end
