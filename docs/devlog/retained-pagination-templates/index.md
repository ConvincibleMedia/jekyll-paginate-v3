# Retained pagination templates and route metadata

Preserve eligible source page/document objects as page one, expose the original template route and resolved descendant path on emitted indexes, and enforce relative native V3 pagination routes.


## Scope

* Preserve an original `Jekyll::Page` or `Jekyll::Document` when expansion produces one variant and page one retains its Jekyll type and container.
* Generate new objects for later indexes and for targets that require another type or container.
* Expose the original unexpanded route as `page.pagination.base` and the resolved descendant fragment as `page.pagination.path`.
* Reject leading slashes in native V3 group and page permalink fragments while retaining root-relative V1 `paginate_path` behaviour.
* Preserve complete frontmatter and existing multi-variant behaviour.
* Add integration coverage and update public documentation and the changelog.


## Stages

* **Route metadata and validation** — complete. Established route context, emitted `base`/`path` metadata and the native V3 relative-fragment contract.
* **Retained page-one emission** — complete. Reuses eligible source objects while preserving position and plugin state.
* **Coverage and documentation** — complete. Added acceptance coverage, public documentation and changelog entries.
* **Verification** — complete. The focused regression suite passes 38 examples and the complete suite passes 234 examples.


## Key decisions and findings

* Preservation is based on effective runtime type/container: pages targeting pages and collection documents targeting self.
* The implicit default `self,shadow` collection mode qualifies a single document variant for preservation.
* Multiple variants always receive independent generated page-one objects; assigning source identity to one variant would be arbitrary and order-dependent.
* `pagination.base` is the original unexpanded template route. `pagination.path` is the resolved group/page route fragment beneath it, without leading or trailing slashes.
* Native V3 pagination routes are template-relative. Only V1 compatibility retains root-relative permalink behaviour.
* A document targeting pages cannot retain identity because the target requires a `Jekyll::Page` in `site.pages`, rather than a `Jekyll::Document` in its source collection.
* Retained page one uses an immutable emission snapshot so in-place title/permalink/frontmatter mutations cannot affect later page construction or grouped-navigation registration.
* All changed Ruby files pass syntax checks. The project-compatible Ruby 2.4/Jekyll 3.10 environment passes the complete RSpec suite: 234 examples, 0 failures (random seed 59810).
* Full-suite verification exposed two retained-template interactions: V2's translated page-one fragment needed to be relative, and captured source-item metadata needed a pre-emission snapshot when the original object became page one. Both are covered by the passing suite.
* Public documentation now explicitly covers retention eligibility, multi-variant behaviour, route metadata on every index, the V2 relative-fragment rule, and V1 as the sole root-relative compatibility exception. The changelog records both breaking route changes and compatibility translation.
* A separate load-only smoke check remains unavailable in the active Ruby 3.4/Jekyll installation because that installation is missing `Jekyll::Filters::URLFilters`; no environment workaround or dependency change was introduced.
