# frozen_string_literal: true

RSpec.describe 'Pagination integration: item resolution and search syntax' do
  it 'resolves mixed search entries across pages and collections with path filters' do
    files = jekyll_merge(
      jekyll_files do
        file 'index.md' do
          frontmatter(
            pagination_template_frontmatter(
              {
                'pagination' => {
                  'enabled' => true,
                  'items' => [
                    { 'pages' => 'docs/*' },
                    { 'products' => '*' }
                  ],
                  'sort' => 'title asc',
                  'per_page' => 50
                }
              }
            )
          )
          contents('Template content')
        end

        folder 'docs' do
          file 'overview.md' do
            frontmatter('layout' => 'listing', 'title' => 'Overview')
            contents('Overview')
          end
        end

        file 'about.md' do
          frontmatter('layout' => 'listing', 'title' => 'About')
          contents('About')
        end
      end,
      collection_document('products', 'camera.md', { 'layout' => 'listing', 'title' => 'Camera', 'permalink' => '/products/camera/' }, 'Camera')
    )
    files = jekyll_merge(files, collection_document('products', 'tripod.md', { 'layout' => 'listing', 'title' => 'Tripod', 'permalink' => '/products/tripod/' }, 'Tripod'))

    jekyll_build(default_site, files: files) do |site,|
      titles = paginator_item_titles(page_by_url(site, '/'))
      expect(titles).to eq(['Camera', 'Overview', 'Tripod'])
    end
  end

  it 'supports a custom split delimiter across items and templates.location' do
    product_template = collection_document(
      'products',
      'catalogue.md',
      {
        'layout' => 'listing',
        'title' => 'Catalogue',
        'permalink' => '/catalogue/',
        'pagination' => {
          'enabled' => true,
          'items' => 'products|posts',
          'per_page' => 20,
          'sort' => 'title asc'
        }
      },
      'Catalogue'
    )
    product_item = collection_document('products', 'item.md', { 'layout' => 'listing', 'title' => 'Product Item', 'permalink' => '/products/item/' }, 'Item')

    files = jekyll_merge(
      jekyll_merge(post_files(1), product_template),
      product_item
    )

    jekyll_build(
      default_site,
      config: {
        'pagination' => {
          'enabled' => true,
          'split' => '|',
          'templates' => {
            'location' => 'pages|products'
          }
        }
      },
      files: files
    ) do |site,|
      generated_document = document_by_url(site, 'products', '/catalogue/')
      titles = paginator_item_titles(generated_document)

      expect(titles).to eq(['Post 01', 'Product Item'])
    end
  end

  it 'respects configured keyword aliases for pages/all/everything' do
    files = jekyll_merge(
      post_files(1),
      jekyll_files do
        file 'index.md' do
          frontmatter(
            pagination_template_frontmatter(
              {
                'pagination' => {
                  'enabled' => true,
                  'items' => 'universe',
                  'sort' => 'title asc',
                  'per_page' => 50
                }
              }
            )
          )
          contents('Template content')
        end

        folder 'docs' do
          file 'faq.md' do
            frontmatter('layout' => 'listing', 'title' => 'FAQ')
            contents('FAQ')
          end
        end
      end
    )
    files = jekyll_merge(files, collection_document('products', 'bundle.md', { 'layout' => 'listing', 'title' => 'Bundle', 'permalink' => '/products/bundle/' }, 'Bundle'))

    jekyll_build(
      default_site,
      config: {
        'pagination' => {
          'enabled' => true,
          'keywords' => {
            'pages' => 'pg',
            'all' => 'collections',
            'everything' => 'universe'
          },
          'templates' => {
            'location' => 'pg'
          }
        }
      },
      files: files
    ) do |site,|
      titles = paginator_item_titles(page_by_url(site, '/'))
      expect(titles).to include('Bundle', 'FAQ', 'Post 01')
    end
  end
end

