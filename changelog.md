# Changelog

## V3

### 1.0.0

* Rebuilt pagination to be more flexible and configurable.
* Filter and sort on any frontmatter key.
* Generate templates by indexing any frontmatter key.
* Compatibility pathways for legacy v1/v2-style setups.

## V2

### 1.9.4

* Introduced broad pagination configuration in `_config.yml` and page frontmatter overrides.
* Paginated collections beyond posts, including multi-collection and `all` collection support.
* Added filtering by category, tag, and locale, including combined filter use.
* Added offsetting, advanced sorting, pagination trails, and richer paginator metadata.
* Included AutoPages to generate pagination pages for tags, categories, and collections.

## V1

### 1.1.0

* Enabled classic Jekyll post pagination from `paginate` and `paginate_path` config.
* Used a single `index.html` template page and generated page 2+ clones under the paginate path.
* Paginated only posts (excluding hidden posts), with basic previous/next navigation fields.
* Exposed the original minimal paginator contract for Liquid templates.