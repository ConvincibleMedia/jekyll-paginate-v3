# frozen_string_literal: true

RSpec.describe 'Pagination integration: configuration options' do
  it 'adds custom paginator item aliases from keywords.items' do
    files = jekyll_merge(
      post_files(2),
      jekyll_files do
        file 'index.md' do
          frontmatter(
            pagination_template_frontmatter(
              {
                'pagination' => {
                  'enabled' => true,
                  'items' => 'posts',
                  'per_page' => 50,
                  'sort' => 'title asc'
                }
              }
            )
          )
          contents('Template content')
        end
      end
    )

    jekyll_build(
      default_site,
      config: {
        'pagination' => {
          'enabled' => true,
          'keywords' => {
            'items' => 'entries'
          }
        }
      },
      files: files
    ) do |site,|
      payload = page_by_url(site, '/').data.fetch('paginator')

      expect(payload).to include('items', 'entries', 'total_items', 'total_entries')
      expect(payload.fetch('entries').map { |item| item.data.fetch('title') }).to eq(['Post 01', 'Post 02'])
    end
  end

  it 'respects templates.location path filters when discovering templates' do
    files = jekyll_merge(
      post_files(2),
      jekyll_files do
        folder 'blog' do
          file 'index.md' do
            frontmatter(
              pagination_template_frontmatter(
                {
                  'title' => 'Blog',
                  'permalink' => '/blog/',
                  'pagination' => {
                    'enabled' => true,
                    'items' => 'posts',
                    'per_page' => 1,
                    'sort' => 'title asc'
                  }
                }
              )
            )
            contents('Template content')
          end
        end

        folder 'docs' do
          file 'index.md' do
            frontmatter(
              pagination_template_frontmatter(
                {
                  'title' => 'Docs',
                  'permalink' => '/docs/',
                  'pagination' => {
                    'enabled' => true,
                    'items' => 'posts',
                    'per_page' => 1,
                    'sort' => 'title asc'
                  }
                }
              )
            )
            contents('Template content')
          end
        end
      end
    )

    jekyll_build(
      default_site,
      config: {
        'pagination' => {
          'enabled' => true,
          'templates' => {
            'location' => {
              'pages' => 'blog/*'
            }
          }
        }
      },
      files: files
    ) do |site,|
      blog_page = page_by_url(site, '/blog/')
      docs_page = page_by_url(site, '/docs/')

      expect(blog_page.data['paginator']).not_to be_nil
      expect(docs_page.data['paginator']).to be_nil
      expect(page_by_url(site, '/docs/page/2/')).to be_nil
    end
  end

  it 'allows equivalent-key lookup to be disabled completely' do
    files = post_files(2) do |index|
      index == 1 ? { 'tags' => ['ruby'] } : { 'tags' => ['jekyll'] }
    end

    files = jekyll_merge(
      files,
      jekyll_files do
        file 'index.md' do
          frontmatter(
            pagination_template_frontmatter(
              {
                'pagination' => {
                  'enabled' => true,
                  'items' => 'posts',
                  'per_page' => 50,
                  'sort' => 'title asc',
                  'filters' => {
                    'tag' => 'ruby'
                  }
                }
              }
            )
          )
          contents('Template content')
        end
      end
    )

    jekyll_build(
      default_site,
      config: {
        'pagination' => {
          'enabled' => true,
          'equivalents' => false
        }
      },
      files: files
    ) do |site,|
      expect(paginator_item_titles(page_by_url(site, '/'))).to eq([])
    end
  end
end

