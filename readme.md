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
    generate: [] # see Template Generation below

    # The following are treated as default config that will be used for all templates unless overridden

    # What to paginate
    items: posts # see Items below
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

  compatibility: # optional: v2 or v1

  syntax:
    separator: '.' # see Nested Keys below
    split: "," # see Split/Delimiter below
  keywords: {} # allows special words like "all" for all collections to be changed
  equivalents: # see Equivalents below
```

The values shown above are the defaults that will apply if you don't even specify these config keys.


## Pagination Templates

Any page/document becomes a template when it has:

```yaml
pagination:
  enabled: true
```

PaginateV3 looks for templates according to the configuration at `pagination.templates.location`, which uses the [Search Format](#search-format). By default this is `pages`, so pagination templates must be site pages. However, for example, you could create a special collection just for your templates, e.g. `index`, and set `pagination.templates.location: index`.

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

### Sorting

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

### Trail

The pagination trail is the display of previous and next page numbers around the current page number. E.g. if the current page is 3, the trail might be 1, 2, 3, 4, 5. You can control how many previous and next page numbers are shown with the `trail.before` and `trail.after` config keys.

### Title and Permalink

The `title` and `permalink` config keys determine the title/URL of index pages produced from the template. Each can use the placeholder `:num` for the page number, while the `title` value also accepts `:title` for the original template title.

Page 1 always inherits the title/permalink from the template directly, i.e. it doesn't use these formats. They apply to pages 2+.

The permalink is resolved relative to the permalink of the template. So `permalink: page/:num` on a template located at `/news` would produce `news` as page 1, and `news/page/2` as page 2, etc. (In v1 compatibility mode, permalinks are always absolute to site root.)

The permalink can be used to create index pages at different filenames and with different extensions, e.g. `permalink: /api/feed-:num.json`.


## Generated Templates

This feature automatically generates templates by indexing frontmatter values. This is the successor to the "AutoPages" feature from V2.

```yaml
pagination:
  templates:
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

You could generate pagination templates very specifically with a filter, for instance:

```yaml
generate:
- items: products
  index: category
  filter: coats, boots
  # generates 2 templates: products with "coats" category, and products with "boots" category
- items: tools, regions
  index: collection
  # generates 2 templates: one for the "tools" collection and one for the "regions" collection
```


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

The special keywords `pages`, `all` and `everything` can be changed with the `pagination.keywords` config (in case you have a collection called "all", for instance).

In the hash form, the hash key is one of the strings above, and the value is a glob pattern. Only file paths that match the glob pattern will be looked at. For instance:

```yaml
items:
  pages: '*' # all pags
  posts: '/blog/*' # posts in the folder 'blog'
```


## Split/Delimiter

In several places where config expects an array, you are allowed to specify the array as a delimited string. The default delimiter is `,`, however you can change this with the config `pagination.syntax.split`. Set to `false` to disable splitting.

When filtering items, by default, frontmatter values are also split on the delimiter to treat them as arrays. This can be disabled/adjusted per filter.


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

The separator `.` can be changed to a different string using the config `pagination.syntax.separator`.


## Equivalents

You can specify frontmatter keys that should be treated as the same frontmatter key. The `equivalents` config is an array of arrays, where the inner array is a set of frontmatter keys to treat as if equivalent.

By default this is set so that `tag` and `tags` are treated as equivalent, as well as `category` and `categories`. So if you filter on either of these, it will be treated the same as filtering on the other.


## Compatibility

PaginateV3 is an enhanced replacement for [PaginateV2](https://github.com/sverrirs/jekyll-paginate-v2) or even [V1](https://github.com/jekyll/jekyll-paginate).

Set `pagination: compatibility: v1` or `v2` in your site config to enable compatibility mode. This does not guarantee that behaviour will be identical to those gems, but it will do its best to read your existing config and interpret it correctly.


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

The term "items" to refer to the items being paginated can be changed with the `pagination.keywords.items` config entry. For instance, in V2 the term was "posts".

In compatibility mode, legacy paginator keys (`page`, `total_pages`, `*_page_path`, `page_trail`, etc., are added alongside the V3 paginator structure.


## Notes

This gem is in an alpha release. It all seems to be working on my end, but it's not been battle-tested. If you encounter any issues please report them or submit a pull request.

Other behavioural notes:

- Hidden content (`hidden: true`) is always excluded from pagination items.
- Index pages are never included in paginated item sets.
- Indexes generated from generated templates are marked with `page.pagination.generated: true`.


## Acknowledgements

This gem drew heavy inspiration, and a good chunk of code, from [PaginateV2](https://github.com/sverrirs/jekyll-paginate-v2) which itself was based on the [original V1 gem](https://github.com/jekyll/jekyll-paginate).
