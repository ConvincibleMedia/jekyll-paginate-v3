# Placeholder pipeline and grouped sorting

Replace naïve token substitution with a central placeholder pipeline and allow current group values to form structural sort paths.


## Scope

* Add canonical `{{ placeholder }}` and optional `raw` or `slugify` filters.
* Retain `:placeholder` as a greedily lexed compatibility syntax only.
* Resolve both syntaxes through one typed, non-recursive pipeline.
* Make exact `group.on` keys available to grouped sort definitions.
* Preserve interpolated sort values as atomic path components.
* Add comprehensive tests and update public documentation.


## Stages

* **Parser and integration** — complete. Established the placeholder model, migrated existing title/permalink/content handling and added structural grouped sorting.
* **Verification and documentation** — complete. Added edge-case and integration coverage, updated documentation and ran the full suite.


## Key decisions and findings

* Placeholder availability is explicitly defined by each context; there is no arbitrary frontmatter interpolation.
* Exact grouping keys are placeholder names. A dotted name is matched against `group.on`, not traversed by the placeholder resolver.
* Canonical and legacy forms differ only during lexing. Both produce the same nodes and use the same validation and resolution pipeline.
* Canonical syntax accepts zero or one representation filter: `raw` or `slugify`.
* Legacy syntax retains greedy token recognition, but no legacy replacement or rendering pipeline remains.
* Liquid-shaped syntax is parsed by PV3 rather than Liquid because PV3 needs exact-key matching, a deliberately smaller grammar and structural sort-path nodes.
* Titles and generated content default group values to `raw`; permalinks and grouped sort fields default them to `slugify`.
* Parsed page patterns are retained internally between group binding and page emission so inserted values remain opaque and cannot introduce further placeholders.
* Resolved sort fields retain an internal segment array; public `page.pagination` data contains only ordinary configuration values.
* Placeholder configuration and grouped sort keys are validated before item-dependent group expansion wherever the context permits.
