# Grouping

The `pagination` config key `group` causes `items` to be first broken up into groups by the specified frontmatter key(s), and then paginated within each group.

For instance, rather than paginating over all `posts` together, they can first be broken down by their `category`. Then all posts with each category can be paginated separately.

This is the successor to, and generalisation of, V2's AutoPages feature, along with [Generated Templates](/docs/generate.md).


## Simple Usage

```yaml
pagination:
  items: products
  group: category
```

`group: <string>` provides a frontmatter key on which to group paginated items. The above example would first group all `products` by their `category`. A new pagination template is created (by duplicating this one) for each category, which filters for that category.

Note that items could end up in multiple groups, for instance if `category` has multiple values.

Every group is identified by the [slugified](/readme.md#slugify) form of its value because it corresponds to a generated URL. Values with the same slug intentionally belong to the same group: for example, `C#` and `C++` both produce `c` and therefore share `/languages/c/`. To keep them separate, group on a field containing unique route keys such as `c-sharp` and `c-plus-plus`.

Group metadata may use the `raw` filter in titles, content and structural sort fields, but never in permalinks. When one slug represents several raw values, the filter is unavailable in every context because there is no single raw value for the group.


### Multi-Level Grouping

You can group on multiple frontmatter keys:

```yaml
pagination:
  items: products
  group: category, subcategory
```

This will form groups according to the unique combinations of the frontmatter keys identified. In the above example, this would group on each `category`/`subcategory` combination.


## Advanced Usage

Specifying `group` as a string is a shorthand. The expanded form is:

```yaml
pagination:
  items: products
  group:
    on: category
```

In the expanded form this allows you to specify additionally:

* `on`: frontmatter key to group on (as before)
* `bunch`: optional Bunched Grouping (see below)
* `filter`: optional filters applied to the frontmatter key.
  * Takes exactly the same format as normal [Filters](/readme.md#filters)
  * Note this config is singular (`filter` not `filters`).
  * You don't need to specify the frontmatter key again (`category: [shoe, coat]`) as the key you're filtering is already specified at `on`. If you wanted only to include only certain keys, just set `filter: [shoe, coat]`.

For multi-level grouping, `group` must be an array. You can intermix the shorthand and expanded group definitions in the array:

```yaml
pagination:
  items: products
  group: # group by category, subcategory, brand
  - category
  - on: subcategory
    filter: [shoe, coat]
  - brand
```


### Group Navigation

When you split pagination by group, the `paginator` object on the resulting index pages gains the `groups` and `group` properties. These allow you to navigate between the groups.

* `groups`: Array of objects representing the group that this index page belongs to. Array has an element for each level of grouping (highest level first). Each element has:
  * `key`: frontmatter key whose indexing generated this group.
  * `current`, `next`, `prev`, `first`, `last`: the current, next, previous, first and last group, where each has:
    * `num`: 1-based group number.
    * `page`: page/document object for page 1 of that group (not set for `current`).
    * `count`: number of items in that group.
    * `start`: group start label/value.
    * `end`: group end label/value (omitted for open-ended groups).
* `group`: shortcut to the deepest entry of `groups` (`groups[-1]`).

The order of groups is determined by the sorting order of the frontmatter key that was grouped.


## Bunched Grouping

By default, grouping is *per unique slugified value* for the frontmatter keys specified. With Bunched Grouping, the frontmatter values are first gathered into bunches of certain ranges of values. The bunch becomes the group, and pagination occurs in each bunch.

```yaml
pagination:
  group:
    on: size # numeric frontmatter key
    bunch: 100 # gather 'size' into bunches of 100
  permalink: "size/{{ size }} page/{{ num }}"
  title: "Size up to {{ size }}"
```

The above would produce index groups where `0 <= size <= 100`, `100 < size <= 200`, etc.

You can bunch frontmatter keys that are **numeric, date/time, or string (into alphabetical groups)**.

The `bunch` definition can be given as:

* Just the bunch size, e.g.
  * `100`
  * `year`
  * `aa`
* Full bunch definition:
  
  ```yaml
  bunch:
    step: 10 # required: size of bunches
      # all other keys optional
    start: 5 # first bunch lowerbound
      # start: 5, step: 10, means first bunch would be 5–15
    grow: 2 # step size multiplicative factor
    min: 10 # minimum step size after growth
    max: 1000 # maximum step size after growth
    total: 8 # max bunch count; final bunch is unbounded
    empty: true # emit empty bunches too
  ```

The size of bunches can change from bunch 1 to n. This can be controlled either by:

* `step`: set to array, e.g. `[10, 100, 1000]` to manually specify how the step size changes. In this example the first bunch would be size 10, the second size 100, and thereafter bunches are size 1000.
* `grow`: bunch size is multiplied by this number at each step. Thus `1` (default) is linear (no growth), `2` means bunch sizes keep doubling, `0.5` means they keep halving, etc. To prevent bunch sizes becoming too big/small, use `max` and `min`.

### Date/Time

If bunching over frontmatter values that are dates/times, you can use `year`, `month`, `day`, `hour`, `minute` and `second` keywords:

```yaml
bunch: year # bunch by year
# or
bunch:
  start: 2026-12-12
  step: month(2) # bunch size starts at 2 months
  grow: 2 # bunch size keeps doubling
  max: 1000 # max bunch size, after growth, is 1000 days
```

* `day(x)`, `month(x)`, `year(x)`, `hour(x)`, `minute(x)`, `second(x)` mean x of that unit. Omit `(x)` to mean one unit.
* If you don't use one of these keywords, numeric values are interpreted as number of days.

`start` also supports:

* `now`/`today` with optional offsets e.g. `now-1` (current time with seconds offset) or `today+2` (current day with day offset)
* `year(today)`, `month(today)`, `hour(now)`, `minute(now)` mean the start of that unit from the present moment. For instance if today is 25 February 2026, then `year(today)` is 1 January 2026 while `month(today)` is 1 February 2026.

### Alphabetic

String frontmatter values can be bunched into alphabetic bunches.

```yaml
bunch: a
# or
bunch:
  start: aa
  step: 2
  other: '0-9'
```

`a` and `aa` in the examples above are specifying the starting point for alphabetical bunching, and whether we consider just the first letter, first two letters, or first three (`aaa`) which is the maximum.

Items that have a value that isn't alphabetical, e.g. numerical, are discarded. However if you set the `other` key they will instead be grouped into an "other" set with the name you give (in the example above, the "other" set is named "0-9").


## Titles, Permalinks and Sorting

When you `group` pagination, the `title` and `permalink` each gain additional placeholders for the values of the frontmatter keys on which you grouped.

`permalink` is treated differently when Grouping is active, being defined in two parts separated by a space. Only the first part gains the additional placeholders.

For instance if you group on `category, subcategory` then `title` and the grouped part of `permalink` gain `{{ category }}` and `{{ subcategory }}` placeholders.

```yaml
pagination:
  items: products
  group: category, subcategory
  title: "{{ title }}"
  permalink: "{{ category }}/{{ subcategory }} page/{{ num }}"
```

* The first part of `permalink` becomes the actual permalink of the templates that are generated for each group. 
* The second part becomes the value of `permalink` in that generated template's `pagination`.
* If only one part is defined, this is treated as the "second part" only.
* If the "first part" is missing or misses out some of the placeholders, these are implicitly added at the front in grouping order.

  Example:

  ```yaml
  pagination:
    items: products
    group: category, subcategory
    title: "{{ title }}"
    permalink: "page/{{ num }}" # only 1 part defined
  ```

  In the above, the first part is implicitly set to `{{ category }}/{{ subcategory }}`.

The same exact group keys are available in `sort` fields:

```yaml
pagination:
  items: products
  group: data.meta.category
  sort: "details.{{ data.meta.category }}.name asc"
```

The placeholder is resolved once from the current group and defaults to its slugified representation. Use `{{ data.meta.category | raw }}` to address a key containing the unmodified group value.


## Note

Groups are identified by the slugified form of their values because every group corresponds to a generated URL. Values that produce the same slug belong to the same group. If those values need separate groups, group on a field containing unique route keys that slugify uniquely.
