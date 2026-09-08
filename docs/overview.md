# Jekyll Paginate V3

Jekyll Paginate V3 is a build-time pagination engine for Jekyll. It discovers pagination templates in the site's content graph, resolves the content selected by each template, and replaces those templates with navigable index pages or collection documents.

* Hand-authored or configuration-generated pagination templates.
* Items sourced from pages, named collections, all collections, or path-filtered combinations.
* Nested-frontmatter filtering with exact, array, regex, existence, range, date/time, include/exclude, and AND/OR matching.
* Stable multi-field sorting, with configurable direction and empty-value placement.
* Single- or multi-level grouping by unique values, alphabetic ranges, numeric ranges, or date/time periods, with group navigation.
* Fixed or variable page sizes, plus limits, offsets, page trails, and complete first/previous/next/last navigation metadata.
* Configurable titles, permalinks, slugification, multiple layouts, and alternate output formats.
* Index output as pages, source-collection documents, shadow pages, named-collection documents, or cloned collections.
* Layered site, layout, and template configuration with custom syntax, keywords, and equivalent frontmatter keys.
* Compatibility modes for `jekyll-paginate` V1 and `jekyll-paginate-v2`.


## Conceptual model

The pipeline works with five main concepts:

* An **item** is a Jekyll page or collection document that may be selected for pagination.
* A **template** is a page or document whose content and frontmatter define a set of indexes. Templates may exist in the source site or be created in memory from configuration.
* A **variant** is a concrete expansion of a template for a particular group and layout combination.
* An **index** is an emitted page or document containing one window of selected items. In `self` mode, the template becomes page 1. Otherwise, and for pages 2+, these indexes are generated.
* A **paginator** is the Liquid-facing object attached to each index. It exposes that index's items and its relationships to the rest of the set.


## Architecture

The runtime is organised by responsibility:

* [`lib/jekyll-paginate-v3.rb`](../lib/jekyll-paginate-v3.rb) loads the plugin and its components.
* [`generators/pagination_generator.rb`](../lib/jekyll-paginate-v3/generators/pagination_generator.rb) is the Jekyll lifecycle adapter. It normalises site configuration, supplies logging and site-mutation callbacks, and invokes the runtime model.
* [`config/`](../lib/jekyll-paginate-v3/config) owns defaults, canonical normalisation, and compatibility translation. Downstream code should consume normalised configuration rather than reinterpret public shorthand.
* [`query/`](../lib/jekyll-paginate-v3/query) resolves the shared site-search format and applies filtering and stable multi-level sorting.
* [`templates/`](../lib/jekyll-paginate-v3/templates) creates configured templates, expands grouping and layout variants, and constructs grouping metadata.
* [`pagination/model/`](../lib/jekyll-paginate-v3/pagination/model) coordinates discovery, item resolution, variant processing, page emission, and cross-index navigation.
* [`pagination/pages/`](../lib/jekyll-paginate-v3/pagination/pages) contains the page, document, and shadow-page adapters used for different output destinations.
* [`pagination/paginator/`](../lib/jekyll-paginate-v3/pagination/paginator) contains the Liquid drops representing pagination state and navigation references.
* [`support/`](../lib/jekyll-paginate-v3/support) and [`utils/`](../lib/jekyll-paginate-v3/utils) provide shared value processing, nested frontmatter traversal, path handling, page-window calculation, formatting, and logging.