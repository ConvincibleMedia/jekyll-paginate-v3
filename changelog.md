# Changelog

## V3

### 0.1.0

* Replaced v2’s `collection`-centric model with an `items` search model (pages, collections, all/everything, optional globs).
* Replaced fixed v2 filters (`category`/`tag`/`locale`) with generic frontmatter filters (`match`, `include`/`exclude`, `min`/`max`, regex, join modes).
* Replaced `sort_field` + `sort_reverse` with a unified multi-level `sort` syntax and explicit empty-value handling.
* Added configurable nested-key access (default `.`), equivalent keys (for example `tag`/`tags`), and delimiter-driven array parsing.
* Folded AutoPages-style generation into `pagination.templates.generate` (driven by `items` + indexed keys) rather than separate v2 `autopages` config.
* Broadened template discovery via `pagination.templates.location` (not just v2-style page templates).
* Standardised paginator payload around `items`/`total_items`.
* Kept explicit compatibility modes (`compatibility: v1` / `v2`) to interpret legacy configuration paths during migration.

## V2

### 1.9.4

* Primary config lived under `pagination` in `_config.yml` (`enabled`, `collection`, `per_page`, `permalink`, `title`, `limit`, `offset`, `sort_field`, `sort_reverse`, `trail`, `indexpage`, `extension`), with page-level frontmatter overrides.
* Paginated `posts` by default, but could paginate a named collection, multiple collections, or special `all`.
* Added first-class filtering by `category`, `tag`, and `locale`; comma-delimited values acted as combined filters.
* Supported advanced sorting, including nested fields via `:` path syntax (for example `author:name:first`).
* Extended paginator payload beyond v1 with `page_path`, `first_page(_path)`, `last_page(_path)`, and `page_trail` (while keeping v1-style fields).
* Marked generated pagination pages with `page.autogen = "jekyll-paginate-v2"` for detection in templates.
* Included optional, experimental `autopages` to generate tag/category/collection index pages from site content.
* Included legacy compatibility mode for old `paginate`/`paginate_path` config (mutually exclusive with new `pagination` mode).

## V1

### 1.1.0

* Enabled only when `site.config['paginate']` was set; read configuration from `paginate` (per-page size) and `paginate_path`.
* Paginated only `site.site_payload['site']['posts']`, always excluding posts with `hidden: true`.
* Selected exactly one template page: `index.html` within the source-to-`paginate_path` hierarchy (preferring the deepest matching path).
* Used the template page as page 1 and cloned it for page 2+ (`site.pages << newpage`), with `newpage.dir` set from `paginate_path`.
* Required `paginate_path` to contain `:num` for numbered pages; raised `ArgumentError` otherwise.
* Exposed minimal paginator/liquid contract: `page`, `per_page`, `posts`, `total_posts`, `total_pages`, `previous_page(_path)`, `next_page(_path)`.
* Computed page counts by ceiling division and raised on invalid page requests (`page > total_pages`).
