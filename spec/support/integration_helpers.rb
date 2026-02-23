# frozen_string_literal: true

module IntegrationHelpers
  # Builds the baseline site definition used by all integration examples.
  #
  # The returned blueprint keeps default config and core layouts in one reusable
  # object so each spec can override only what it needs via `jekyll_build`.
  def default_site
    listing_layout_markup = <<~HTML
      <!doctype html>
      <html>
        <body>
          <main id="content">
            {{ content }}
          </main>
          {% if paginator %}
            <p id="current-page">{{ paginator.page }}</p>
            <p id="total-pages">{{ paginator.total_pages }}</p>
            <ul id="items">
              {% for item in paginator.items %}
                <li>{{ item.title }}</li>
              {% endfor %}
            </ul>
            <ul id="alias-items">
              {% if paginator.posts %}
                {% for item in paginator.posts %}
                  <li>{{ item.title }}</li>
                {% endfor %}
              {% endif %}
            </ul>
            <ol id="trail">
              {% if paginator.page_trail %}
                {% for entry in paginator.page_trail %}
                  <li>{{ entry.num }}|{{ entry.path }}|{{ entry.title }}</li>
                {% endfor %}
              {% endif %}
            </ol>
          {% endif %}
        </body>
      </html>
    HTML

    jekyll_blueprint(
      config: {
        'title' => 'Spec Site',
        'url' => 'https://example.test',
        'plugins' => ['jekyll-paginate-v3'],
        'collections' => {
          'products' => { 'output' => true },
          'guides' => { 'output' => true },
          'notes' => { 'output' => true }
        },
        'pagination' => {
          'enabled' => true
        }
      },
      files: jekyll_files do
        folder '_layouts' do
          file 'default.html' do
            contents(listing_layout_markup)
          end

          file 'listing.html' do
            frontmatter('layout' => 'default')
            contents('{{ content }}')
          end

          file 'post.html' do
            frontmatter('layout' => 'default')
            contents('<article>{{ content }}</article>')
          end

          file 'autopage_tags.html' do
            frontmatter('layout' => 'default')
            contents('{{ content }}')
          end

          file 'autopage_category.html' do
            frontmatter('layout' => 'default')
            contents('{{ content }}')
          end

          file 'autopage_collection.html' do
            frontmatter('layout' => 'default')
            contents('{{ content }}')
          end
        end
      end
    )
  end

  # Returns canonical frontmatter for a pagination template.
  #
  # Use with the harness file DSL:
  # `frontmatter(pagination_template_frontmatter(...))`
  def pagination_template_frontmatter(overrides = {})
    defaults = {
      'layout' => 'listing',
      'title' => 'Listing',
      'pagination' => {
        'enabled' => true
      }
    }
    jekyll_merge(defaults, overrides)
  end

  # Produces a hash of post file paths and document bodies.
  #
  # The optional block receives the 1-based index and can return additional
  # frontmatter overrides for each post.
  def post_files(total_count, start_day: 1)
    jekyll_files do
      folder '_posts' do
        total_count.times do |offset|
          number = offset + 1
          day = start_day + offset
          slug = format('post-%02d', number)
          filename = "2026-01-#{format('%02d', day)}-#{slug}.md"

          frontmatter_data = {
            'layout' => 'post',
            'title' => "Post #{format('%02d', number)}",
            'date' => "2026-01-#{format('%02d', day)} 12:00:00 +0000"
          }
          frontmatter_data = frontmatter_data.merge((yield(number) || {})) if block_given?

          file filename do
            frontmatter(frontmatter_data)
            contents("Post body #{number}")
          end
        end
      end
    end
  end

  # Builds one collection document as a nested files hash.
  def collection_document(collection_label, filename, frontmatter_data = {}, body = '')
    jekyll_files do
      folder "_#{collection_label}" do
        file filename do
          frontmatter(frontmatter_data)
          contents(body)
        end
      end
    end
  end

  # Finds generated pagination pages in site.pages.
  def generated_pagination_pages(site)
    site.pages.select { |item| item.data.dig('pagination', 'index') }
  end

  # Finds generated pagination documents in a specific collection.
  def generated_pagination_documents(site, collection_label)
    collection = site.collections.fetch(collection_label)
    collection.docs.select { |item| item.data.dig('pagination', 'index') }
  end

  # Finds a page by URL.
  def page_by_url(site, url)
    site.pages.find { |page| page.url == url }
  end

  # Finds a collection document by URL.
  def document_by_url(site, collection_label, url)
    site.collections.fetch(collection_label).docs.find { |document| document.url == url }
  end

  # Extracts paginator item titles from a generated page/document.
  def paginator_item_titles(item, key: 'items')
    payload = item.data.fetch('paginator')
    items = payload.fetch(key)
    items.map { |entry| entry.data.fetch('title') }
  end

  # Extracts trail page numbers from paginator payload.
  def paginator_trail_numbers(item)
    payload = item.data.fetch('paginator')
    entries = payload.fetch('page_trail') || []

    entries.map do |entry|
      if entry.respond_to?(:num)
        entry.num
      else
        entry['num']
      end
    end
  end
end
