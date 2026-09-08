# Group indexes

Grouping currently expands a pagination template into leaf indexes and consumes the originating template. Group indexes should instead allow the originating template and intermediate groups to paginate over the groups immediately beneath them.


## Core model

Grouping forms a tree. Each group node is represented by the page-one page or document for that group.

* The originating template becomes the root group index.
* An intermediate group index paginates over the page-one objects of its immediate child groups.
* A leaf group index retains the existing behaviour and paginates over its matched source items.

A group index uses the normal `page.paginator` shape without a parallel group-paginator API. Its `items`, counts, index references, trails and page-size behaviour work exactly as for any other pagination index; its items simply happen to be generated pages or documents. A small value in `page.pagination` may identify whether the page is a group index or an item index without changing the paginator interface.


## Multi-level grouping

For `category, subcategory`, the generated hierarchy is:

```text
/catalogue/                         paginates category pages
/catalogue/page/2/                  more category pages
/catalogue/books/                   paginates subcategory pages
/catalogue/books/page/2/            more subcategory pages
/catalogue/books/hardback/          paginates source items
/catalogue/books/hardback/page/2/   more source items
```

Because a group-index item is itself a page or document, layouts can inspect its paginator directly. This permits nested output such as a category list containing each category page's current subcategory window:

```liquid
{% for category in paginator.items %}
  {{ category.title }}
  {% for subcategory in category.paginator.items %}
    {{ subcategory.title }}
  {% endfor %}
{% endfor %}
```

Reaching into a child paginator exposes that child's current page only; it does not implicitly bypass pagination or load every descendant group.


## Configuration direction

Group indexes should initially be opt-in so existing grouped templates retain their current output. Configuration should allow a default page size for group indexes and optional per-level overrides. Ordinary `pagination.per_page` continues to control pagination of source items at leaf groups.

The implementation should first build the complete group tree, then emit leaf and intermediate pages so every parent paginator can receive the concrete page-one objects of its children.
