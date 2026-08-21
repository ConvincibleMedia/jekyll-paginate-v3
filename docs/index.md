# Jekyll Paginate V3

Jekyll Paginate V3 is a build-time pagination engine for Jekyll. It discovers pagination templates in the site's content graph, resolves the content selected by each template, and replaces those templates with navigable index pages or collection documents.

The project extends the model established by earlier Jekyll pagination plugins while treating filtering, sorting, grouping, generated templates, layouts, and output destinations as parts of one coherent pipeline. Compatibility layers for V1 and V2 are kept at defined boundaries rather than shaping the core runtime.

This page is an architectural orientation to the repository. For installation, configuration, Liquid data, and examples, see the [README](../readme.md).


## Conceptual model

The pipeline works with five main concepts:

* An **item** is a Jekyll page or collection document that may be selected for pagination.
* A **template** is a page or document whose content and frontmatter define a set of indexes. Templates may exist in the source site or be created in memory from configuration.
* A **variant** is a concrete expansion of a template for a particular group and layout combination.
* An **index** is an emitted page or document containing one window of selected items. The first index replaces its source template; later indexes extend the set.
* A **paginator** is the Liquid-facing object attached to each index. It exposes that index's items and its relationships to the rest of the set.

At a high level, each Jekyll build follows this sequence:

1. Normalise site configuration into the internal V3 form.
2. Create any configured in-memory templates.
3. Snapshot the site's candidate items so emitted indexes cannot feed back into later item searches.
4. Discover templates and merge their site, layout, and local configuration.
5. Expand each template into its grouped and layout-specific variants.
6. Resolve, filter, sort, offset, and limit the items for each variant.
7. Divide the result into page windows and emit the corresponding Jekyll objects.
8. Connect paginator navigation, trails, and grouped-set relationships after the relevant indexes exist.


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