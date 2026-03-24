# Roadmap

## Ideas for features

* `empty: false` setting to delete pagination templates that paginate over zero items.
* `num` formatting for instance to make it more I18n-friendly (1,000.00 vs 1.000,00).
* Allow control over how page 1 is handled:
  * `replace` (default): as per current behaviour: pagination templates, when found and processed, are replaced with the index page for page 1.
  * `preserve`: pagination templates are never modified. Page 1 is generated as an *additional* page/doc. Permalink treatment for pages 2+ is also applied to page 1 (e.g. resulting in a ../page/1 -style url).
  * `delete`: as `preserve` but as a final step, the original pagination template doc/page is deleted.
* Auto-create an index at each level of a multi-level grouping.
* New sorting styles: `asc:cyclic`, `asc:frequency`, `asc:zigzag` (min, max, next-min, next-max).