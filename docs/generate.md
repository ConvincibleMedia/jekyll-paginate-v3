# Generated Templates

This feature creates pagination templates from configuration definitions. It is the successor to V2's AutoPages, along with [Grouping](/docs/group.md).


## Configuration

Each element of the array at `pagination: templates: generate` is a specification for a template to generate. The specification is the `pagination` config that will be applied to that template.

```yaml
pagination:
  templates:
    generate:
    - items: products
    - items: posts
      filters:
        category: 'blog'
      layout: blog-index
    - items: news
      frontmatter:
        latest: 17
      content: |
        Welcome to the News page.
```

Generated template specifications can also include the keys `frontmatter` and `content`.

* `frontmatter` defines arbitrary frontmatter that will be set on the generated pagination template.
* `content` defines the Markdown content of the pagination template. When grouping is active, it can contain placeholders for the exact active `group.on` keys. See [Placeholders](/docs/placeholders.md).


## Grouping

Combine generated templates with [Grouping](/docs/group.md) for use-cases like automatically generating paginated indexes for each site category or tag.

```yaml
pagination:
  templates:
    generate:
    - items: posts
      group: tag
```
