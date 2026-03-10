# Jekyll Paginate V3

![Alpha](https://img.shields.io/badge/status-alpha-red)

Flexible and configurable pagination for Jekyll 3.8.5+.

* Paginate pages or collection documents.
* Filter items by any frontmatter key (including nested keys).
* Generate pagination templates automatically from any frontmatter values.

Like previous versions, to use pagination you must create "templates":

* A **template** is a page/document in which you have set `pagination: enabled: true`.
* These pages/documents will be removed, but their settings/contents are used to generate an **index** page/document for each page in the pagination (e.g. page 1, page 2, page 3).
* Each index gains a `paginator` variable which you can use to iterate over the **items** that have been paginated to that page (e.g. items 1–9 on page 1, 10–18 on page 2, etc.).


## Quickstart

Include the plugin in your project:

```ruby
# Gemfile
group :jekyll_plugins do
  gem 'jekyll-paginate-v3'
end
```

Enable pagination in your site config (you can also configure how it works, here):

```yaml
# _config.yml
pagination:
  enabled: true
```

Create pagination templates (by default these must be pages, not collection documents). Each template specifies what it paginates:

```yaml
# post-index.md - example
---
layout: post-listing # indexes will use this layout
pagination:
  enabled: true
  items: posts # paginate over site posts
---
```

Or alternatively (or in addition), specify that pagination templates should be generated:

```yaml
# _config.yml
pagination:
  enabled: true
  templates:
    generate:
    - items: posts # template to paginate posts
      layout: post-listing.html
    - items: news # template to paginate 'news' collection
      layout: news-listing.html
```

The paginator will find these templates and create indexes from them (pages with a certain number of the paginated items assigned to them).

Then on the layouts used by the created indexes:

```liquid
{% for item in paginator.items %}
  <h2><a href="{{ item.url }}">{{ item.title }}</a></h2>
{% endfor %}

{% if paginator.prev %}
  <a href="{{ paginator.prev.page.url }}">Newer</a>
{% endif %}

{% if paginator.next %}
  <a href="{{ paginator.next.page.url }}">Older</a>
{% endif %}
```


## Configuration

```yaml
pagination:
  enabled: true # if not true, globally disables pagination

  # Settings for templates
  templates:
    # Where in site to look for templates
    location: pages # see Search Format below

    # Auto-generate templates
    generate: [] # see Generated Templates below

    # The following are treated as default config that will be used for all templates unless overridden

    # What to paginate
    items: posts # see Items below
    # Where indexes are emitted for templates
    collection: self, shadow # see Collection Targets below
    filters: [] # see Filters below
    sort: date desc # see Sorting below
    # How items are divided per page
    per_page: 10 # int, or array of ints for variable page sizes
    limit: 0 # paginate no more than x items
    offset: 0 # skip first x items
    # How the pagination trail works
    trail:
      before: 2 # X pages shown before current page
      after: 2 # X pages shown after current page
    # Title for index pages
    title: ':title - page :num'
    # URL of index pages
    permalink: /page/:num # relative to the template's permalink

  # Compatibility mode
  compatibility: # optional: 'v2' or 'v1'

  # Advanced settings
  syntax:
    separator: '.' # see Nested Keys below
    split: ',' # see Split/Delimiter below
  keywords: # see Keywords below
  equivalents: # see Equivalents below
```

Where values are shown above, these are the defaults that will apply if you don't even specify these config keys.


## Pagination Templates

Any page/document becomes a template when it has:

```yaml
pagination:
  enabled: true
```

However, PaginateV3 needs to *find* this page/document. It looks for templates according to the configuration at `pagination.templates.location`, which uses the [Search Format](#search-format). By default this is `pages`, so pagination templates must be site pages. However, for example, you could create a special collection just for your templates, e.g. `index`, and set `pagination.templates.location: index`.

The template can have additional configuration, which overrides the defaults set in `site.pagination`. You can also place `pagination` configuration in a layout used by a pagination template. The configuration options on both are merged, with the template having priority (unless in v2 compatibility mode, in which the layout has priority).

### Created Index Pages

Having found a template, PaginateV3 creates index pages as required. E.g. if your settings specify 10 items to a page, and there are 15 items, it will create two index pages (for items 1–10 and 11–15). The first index page replaces the pagination template itself. Further index pages are additions. They will all inherit the settings, frontmatter and content of the template.

`pagination.templates.collection` controls the type of page/document that created index pages will be by default.

```yaml
pagination:
  enabled: true
  templates:
    collection: self, shadow # default
```

You can override this per template with `pagination.collection` on the template itself.

The value can either be a single string (e.g. `pages`), which treats all index pages the same, or two strings (e.g. `[self, pages]`), which gives the treatment for page 1 and pages 2+ separately. The strings can be any of the following:

* `pages`: create index pages as site pages.
* `<collection_name>`: create index pages as documents in the given collection.
* `self`: create index pages in the same collection as the template.
* `shadow`: create index pages as site pages, but make those pages respond to `page.collection` (this will return the collection of the template).
* `clone`: create index pages as documents in a new collection called `<source_collection>_indexes` (created automatically if missing).

If your site works with collections, each of `self`, `shadow` and `clone` have pros and cons. You should choose which mode depending on how you site iterates and works with collections.

| Value    | Effect | Pros | Cons |
| -------- | ------ | ---- | ---- |
| `self`   | True document in original collection | Full document semantics | `{% for item in site.<collection> %}` will include index pages 2+ |
| `shadow` | Page with collection metadata only | Keeps `site.<collection>` clean | Not a true collection member |
| `clone`  | True document in `<source>_indexes` | Keeps document semantics and separates indexes from source collection loops | Introduces an additional collection |

### Items

Pagination templates must specify what items they paginate over with the `items` key. This key uses the [Search Format](#search-format) to identify where to look for items to paginate over.

The number of items that appear per page are controlled with:

| Key | Default | Effect |
| --- | ------- | ------ |
| `per_page` | 10 | Number of items per index page, or an array where the nth value is used for page n (and the last value repeats thereafter). Example: `per_page: [5, 2, 10]` gives page sizes 5, 2, 10, 10, 10... |
| `limit`    | 0  | Include only the first X items (0 = disabled) |
| `offset`   | 0  | Skip first X items |

### Filters

Filters reduce the items to paginate over according to certain criteria on their frontmatter.

```yaml
pagination:
  filters:
    <frontmatterkey>: <definition>
```

The `<definition>` can be in these forms:

```yaml
filters:
  category: news # frontmatter 'category' must be, or include, 'news'
  product: /^sh/ # 'product' must start with 'sh' (any regex allowed)
  name:
    match: cat # name must match 'cat'
    mode: auto # match mode (see below)
    split: true # whether/how to convert value to array
  rating:
    min: 3 # minimum numeric value (optional)
    max: 5 # maximum numeric value (optional)
    mode: min-exclusive max-inclusive # optional range-bound inclusivity
  tags: [news, blog] # 'tags' must be or include 'news' or 'blog'. Array elements can be any definition form.
  key:
    include: [news, /^s/] 'key' should match filters in array
    join: and # filters in array should all match
    exclude: internal # 'key' cannot be 'internal'
```

That is:

* String: simple match
* Regex: specified by a string starting/ending with `/` followed by optional regex flag
* Hash with:
  * `match`: string/regex to match on
  * `mode`: optional, can be:
    * `auto` (default): frontmatter value either matches exactly, or is an array, and contains the match
    * `strict` frontmatter value must match exactly
    * `only`: like `auto` but if array, must be the only array item
    * `first`/`first(N)` (e.g. `first(3)`): like `auto` but if array, only the first (N) array elements are considered.
  * `split`: overrides `split` from global config, for this filter only. Set this to `false` to disable splitting of the frontmatter value. Defaults to true: frontmatter values will be treated as arrays if they can be split.
* Range with `min` and/or `max` for numeric values.
  * `min`/`max` are inclusive by default, and can be:
    * Numeric e.g. `3`, `0.4`
    * Date/time e.g. `2026-01-01`, `2026-01-01 12:00:00`
    * Keyword `today` or `now`
      * `today` means current day, and supports optional whole-day offsets (e.g. `today`, `today+1`, `today-2`).
      * `now` means current time, and supports optional whole-second offsets (e.g. `now`, `now+60`, `now-120`).
  * `mode` (optional) controls inclusivity:
    * `min-exclusive`
    * `max-exclusive`
    * `min-exclusive max-exclusive`
* Array (or delimited string): combine several filters with an OR operation
* Hash with:

  * `include`: whitelist filters
  * `exclude`: blacklist filters
  * `join`: override the default OR operation to an AND (`and`) within `include`/`exclude`.
  
  This format can be used to build up arbitrarily complex, nested filters.

A synthetic `collection` frontmatter key is available to match on the document's collection label.

### Sorting

`sort` determines the sort order of paginated items. It supports multi-level sort definitions:

```yaml
pagination:
  sort:
  - featured desc
  - author.name asc empty:last
  - date desc
```

The syntax is `field [options]`. The options are:

* direction: `asc`/`ascending` (default) or `desc`/`descending`.
* empty handling: `empty:first` or `empty:last` (default) specifies how to handle items that lack that frontmatter entirely.

`sort` doesn't have to be an array, a single sort field can just be a string directly.

### Trail

The pagination trail is the display of previous and next page numbers around the current page number. E.g. if the current page is 3, the trail might be 1, 2, 3, 4, 5. You can control how many previous and next page numbers are shown with the `trail.before` and `trail.after` config keys.

### Title and Permalink

The `title` and `permalink` config keys determine the title/URL of index pages produced from the template. Each can use the placeholder `:num` for the page number, while the `title` value also accepts `:title` for the original template title.

Page 1 always inherits the title/permalink from the template directly, i.e. it doesn't use these formats. They apply to pages 2+.

The permalink is resolved relative to the permalink of the template. So `permalink: page/:num` on a template located at `/news` would produce `news` as page 1, and `news/page/2` as page 2, etc. (In v1 compatibility mode, permalinks are always absolute to site root.)

The permalink can be used to create index pages at different filenames and with different extensions, e.g. `permalink: /api/feed-:num.json`.


## Generated Templates

See [Generated Templates](/lib/jekyll-paginate-v3/templates/readme.md) for detailed readme about this feature.


## Search Format

A number of config keys require that you specify "where in the site to look". These all accept the same format:

1. String: `pages`, a collection label like `posts`, `all`, or `everything`
2. Hash: `{ posts: '*' }`, `{ pages: 'blog/*' }`
3. Array of the above (look in several places) (can be delimited string)

| Option | Effect |
| ------ | ------ |
| `pages` | Look in site pages |
| Collection label | Look in the documents of that collection |
| `all` | Look in the documents of all collections |
| `everything` | `pages` + `all` |

In the hash form, the hash key is one of the strings above, and the value is a glob pattern. Only file paths that match the glob pattern will be looked at. For instance:

```yaml
items:
  pages: '*' # all pages
  posts: '/blog/*' # posts in the folder 'blog'
```


## Split/Delimiter

In several places where config expects an array, you are allowed to specify the array as a delimited string. The default delimiter is `,`, however you can change this with the config `pagination.syntax.split`. Set to `false` to disable splitting.

When filtering items, by default, frontmatter values are also split on the delimiter to treat them as arrays. This can be disabled/adjusted per filter by setting `split` on the filter.


## Nested Keys

Wherever you need to specify a frontmatter key, you can access nested keys using a separator. By default this is `.`, so `product.name` accesses the `name` key under the `product` key.

The nested access format will also read across complex arrays, mapping them as needed. For instance:

```yaml
data:
  categories:
  - name: Shoes
    size: 34
  - name: Coats
    size: 12
```

`data.categories.size` would access the array `[34, 12]`.

The separator `.` can be changed to `:` using the config `pagination.syntax.separator`.


## Paginator

`page.paginator` is available on the index pages that are generated. This has the following properties:

* `items`: Array of items (actual docs/pages) paginated to this index page.
* `total_items`: Total number of all items across all indexes.
* `total_indexes`: Total number of index pages in this pagination.
* `current`, `next`, `prev`, `first`, `last`: objects representing the current, next, previous, first and last index pages, where each has:
  
  * `num`: Page number of this index.
  * `page`: The actual page/doc object of this index (not set for `current`) on which you can access `url` as normal, to get a link to that index page.
  * `count`: Number of items paginated to this index.
  * `start`: 1-based index of the first item on this index page.
  * `end`: 1-based index of the last item on this index page.
  
  `next`/`prev` will just be `nil` if there is no next/prev index page.
* `trail`: Array of trail objects, where each has:
  * `num`: Page number of the index.
  * `page`: The actual page/doc object (not set for current page) on which you can access `url` as normal, to get a link to that page.
  * `current`: `true` if this trail item is the current page.
  * `distance`: Relative page number. 0 for current page, positive for pages after, negative for pages before.

`page.pagination` also remains available, being a copy of the pagination settings from the template that generated this index (minus `enabled`). This allows you to read back settings like `per_page`, `limit`, etc., if needed.


## Equivalents

You can specify frontmatter keys that should be treated as the same frontmatter key. The `equivalents` config is an array of arrays, where the inner array is a set of frontmatter keys to treat as if equivalent.

By default this is set so that `tag` and `tags` are treated as equivalent, as well as `category` and `categories`. So if you filter on either of these, it will be treated the same as filtering on the other.


## Keywords

The following keywords have special meaning in certain contexts within pagination configuration. If these clash with your site (e.g. you have a collection called 'all') then you can change the keyword with `pagination.keywords.<keyword>: 'new_keyword'`.

* `pages`
* `all`
* `everything`
* `self`
* `shadow`
* `clone`
* `now`
* `today`
* `day`
* `month`
* `year`
* `hour`
* `minute`
* `second`
* `items`


## Compatibility

PaginateV3 can be used as an enhanced replacement for [PaginateV2](https://github.com/sverrirs/jekyll-paginate-v2) or even [V1](https://github.com/jekyll/jekyll-paginate).

Set `pagination: compatibility: v1` or `v2` in your site config to enable compatibility mode. This does not guarantee that behaviour will be identical to those gems, but it will do its best to read your existing config and interpret it as you originally intended.

### V2

In compatibility mode, legacy paginator keys (`page`, `total_pages`, `*_page_path`, `page_trail`, etc., are added alongside the V3 paginator structure.


## Notes

This gem is in an alpha release. It all seems to be working on my end, but it's not been battle-tested. If you encounter any issues please report them or submit a pull request.

Other behavioural notes:

- Hidden content (`hidden: true`) is always excluded from pagination items.
- Index pages are never included in paginated item sets.
- Indexes generated from generated templates are marked with `page.pagination.generated: true`.


## Acknowledgements

This gem drew heavy inspiration, and a good chunk of code, from [PaginateV2](https://github.com/sverrirs/jekyll-paginate-v2) which itself was based on the [original V1 gem](https://github.com/jekyll/jekyll-paginate).
