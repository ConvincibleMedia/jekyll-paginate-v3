# Roadmap

* Num is I18n aware

New config to allow us to control how page1 is handled.
pagination: template: can be set as global default or at template level
if 'replace', as per current behaviour: pagination templates, when found and processed, are replaced with the index page for page 1
if 'preserve', then pagination templates are never modified. page 1 is generated as an additional page/doc. permalink treatment for pages 2+ is also applied to page 1 (e.g. resulting in a ../page/1 -style url)
if 'delete', then as 'preserve' but as a final step, the original pagination template doc/page is deleted
default: replace



new: index at each level of multi-level grouping


## Sorting

New sorting styles:

asc:cyclic

asc:frequency

zigzag: min, max, next-min, next-max...

