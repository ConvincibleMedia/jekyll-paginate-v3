# Jekyll Paginate V3

Robust, highly configurable pagination for Jekyll 3.8.5+.

* Paginate any content source (pages, collections).
* Filter on any frontmatter key (including nested keys).
* Generate pagination templates automatically from frontmatter values.

Like previous versions, pagination works by creating "templates":
* A **template** is a page/document in which you have set `pagination: enabled: true`.
* These pages/documents will be removed, but their settings/contents are used to generate an **index** page/document for each page in the pagination (e.g. page 1, page 2, page 3).
* Each index gains a `paginator` variable which you can use to iterate over the **items** that have been paginated to that page (e.g. items 1–9 on page 1, 10–18 on page 2, etc.).

PaginateV3 is an enhanced replacement for PaginateV2. Compatibility modes for [jekyll-paginate](https://github.com/jekyll/jekyll-paginate) ("v1") and [jekyll-paginate-v2](https://github.com/sverrirs/jekyll-paginate-v2) are included.


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

Create pagination templates (by default these must be pages on the site, not collection documents). Each template specifies what it paginates:

```yaml
# post-index.md - example
---
layout: post-listing # indexes will use this layout
pagination:
  enabled: true
  items: posts # paginate over site posts
---
```

Then on the layouts used by the generated indexes:

```liquid
{% for item in paginator.items %}
  <h2><a href="{{ item.url }}">{{ item.title }}</a></h2>
{% endfor %}

{% if paginator.previous_page %}
  <a href="{{ paginator.previous_page_path }}">Newer</a>
{% endif %}

{% if paginator.next_page %}
  <a href="{{ paginator.next_page_path }}">Older</a>
{% endif %}
```


## Configuration

```yaml
pagination:
  enabled: false # global disable

  # Defaults that will be used for all templates
  items: posts # what to paginate
  filters: {} # filter which pages to include in pagination

  per_page: 10 # how many items per page
  offset: 0 # skip first x items
  limit: 0 # paginate no more than x items
  trail: # number of pages in page trail around current page
    before: 0
    after: 0

  sort: date desc # how to sort paginated items

  # Index page defaults
  permalink: /page/:num/
  title: ':title - page :num'
  indexpage: index
  extension: html

  templates:
    location: pages # where in site to look for templates
    generate: [] # auto-generate templates

  compatibility: # optional: v2 or v1
  nested_key_separator: '.' # or ':'
  split: "," # delimiter used where array-like fields accept delimited strings
  keywords:
    pages: pages
    all: all
    everything: everything
    now: now
    items: items # set to posts for v2-style payload
  equivalents:
    - [tag, tags]
    - [category, categories]
```


## Pagination Templates

Any page/document becomes a template when it has:

```yaml
pagination:
  enabled: true
```

PaginateV3 looks for templates according to the configuration at `pagination.templates.location`, which uses the [Search Format](#search-format). By default this is `pages`, so pagination templates must be site pages. However, for example, you could create a special collection just for your templates, e.g. `index`, and set `pagination.templates.location: index`.

### Items

Pagination templates must specify what items they paginate over with the `items` key. This key uses the [Search Format](#search-format) to identify where to look for items to paginate over.

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
  tags: [news, blog] # 'tags' must be or include 'news' or 'blog'. Array elements can be any definition form.
  key:
    include: [news, /^s/] 'key' should match filters in array
    join: and # filters in array should all match
    exclude: internal # 'key' cannot be 'internal'
```

- Match mode can be:
  - `strict` frontmatter key must match exactly
  - `auto` (default): frontmatter either matches exactly, or is an array, and contains the match
  - `only`: like `auto` but if array, must be the only array item
  - `first`/`firstN` (e.g. `first3`): like `auto` but if array, only the first (N) array elements are considered
- The `split` option overrides `split` from global config, for this filter only. Set this to `false` to disable splitting of the frontmatter value.
- Range matches are inclusive; `min`/`max` can be numeric, datetime, or now-relative string (`now`, `now+1`, `now-1`, etc.). The `now` keyword is configurable at `pagination.keywords.now`.
- A synthetic `collection` frontmatter key is available to match on the document's collection label.
- Arrays can be specified as delimited strings.


## Sorting

`sort` determines the sort order of paginated items. It supports multi-level sort definitions:

```yaml
pagination:
  sort:
    - featured desc
    - author.name asc empty:last
    - date desc
```

The syntax is `field [options]`. `sort` doesn't have to be an array, a single sort field can just be a string directly.

Options:

- direction: `asc`/`ascending` (default) or `desc`/`descending`
- empty handling: `empty:first` or `empty:last` (default) specifies how to handle items that lack that frontmatter entirely


## Generated Templates

This feature automatically generates templates by indexing frontmatter values. This is based on the "AutoPages" feature from V2.

```yaml
pagination:
  templates:
    location: pages
    generate:
      - items: posts # Search Format: what items to consider
        index: tag # what frontmatter keys to index
        #filters: # optionally filter those items (same format as pagination filters)
        layout: tags.html
        permalink: /tag/:tag/
        title: 'Posts tagged :tag' # placeholders for the indexed keys
      - items: products
        index: category, subcategory # multi-level indexing
        filter: /^s/ # singular 'filter' is a shorthand to apply filter to the indexed frontmatter key(s)
        layouts: [autopage_category.html] # multiple layouts
        frontmatter: # add arbitrary frontmatter
          section: catalogue
        #location: # override whether this generated template will be in 'pages' or a collection name
```

The generator will look in all the items you've identified and index them by the values in the frontmatter key(s) you specify on `index`.

For instance if you look in `posts` and index on `tags`, it might find posts with the tags "cat" and "dog". It will create a pagination template for "cat" and "dog", each of which will paginate posts with the tags "cat" and "dog" respectively.


## Search Format

A number of config keys require that you specify "where to look". These all accept the same format:

1. String: `pages`, a collection label like `posts`, `all`, `everything`
2. Hash: `{ posts: '*' }`, `{ pages: 'blog/*' }`
3. Array of the above (look in several places) (can be delimited string)

| Option | Effect |
| ------ | ------ |
| `pages` | Look in site pages |
| Collection label | Look in the documents of that collection |
| `all` | Look in the documents of all collections |
| `everything` | `pages` + `all` |

The special keywords `pages`, `all` and `everything` can be changed with the `pagination.keywords` config (in case you have a collection called "all", for instance).

In the hash form, the hash key is one of the strings above, and the value is a glob pattern. Only file paths that match the glob pattern will be looked at.


## Delimiters

In several places where config expects an array, you are allowed to specify the array as a delimited string. The default delimiter is `,`, however you can change this with the config `pagination.delimiter`.

When filtering items, by default, frontmatter values are also split on the delimiter to treat them as arrays. This can be disabled per filter.

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

The separator `.` can be changed to a different string using the config `pagination.nested_key_separator`.


## Equivalents

You can specify frontmatter keys that should be treated as the same frontmatter key. The `equivalents` config is an array of arrays, where the inner array is a set of frontmatter keys to treat as if equivalent.

By default this is set so that `tag` and `tags` are treated as equivalent, as well as `category` and `categories`. So if you filter on either of these, it will be treated the same as filtering on the other.


## Compatibility

Set `pagination: compatibility: v1` or `v2` in your site config to enable compatibility mode for prior Jekyll Pagination gems. This does not guarantee that behaviour will be identical to those old gems, but it will do its best to read your existing config and interpret it correctly. Migrate your config and approach to match this gem's expectations when you can.


## Paginator

`page.paginator` is available on the index pages that are generated. This has the following properties:

- `items`, `total_items`
- `page`, `per_page`, `total_pages`
- `previous_page`, `previous_page_path`
- `next_page`, `next_page_path`
- `first_page`, `first_page_path`
- `last_page`, `last_page_path`
- `page_trail`

The term "items" to refer to the items being paginated can be changed with the `pagination.keywords.items` config entry. For instance, in V2 the term was "posts".


## Notes

- Hidden content (`hidden: true`) is always excluded from pagination items.
- Index pages are never included in paginated item sets.
- Indexes generated from generated templates are marked with `page.pagination.generated: true`.


## Acknowledgements

This gem drew heavy inspiration, and a good chunk of code, from the [jekyll-paginate-v2](https://github.com/sverrirs/jekyll-paginate-v2) gem which itself was based on the original design of [jekyll-paginate](https://github.com/jekyll/jekyll-paginate).