# frozen_string_literal: true

RSpec.describe 'Pagination integration: compatibility v2 autopages variants' do
  it 'migrates legacy categories autopages config with legacy token aliases' do
    files = post_files(2) do |index|
      index == 1 ? { 'category' => 'news' } : { 'category' => 'updates' }
    end

    jekyll_build(
      default_site,
      config: {
        'pagination' => {
          'compatibility' => 'v2'
        },
        'autopages' => {
          'enabled' => true,
          'categories' => {
            'enabled' => true,
            'layout' => 'autopage_category.html',
            'permalink' => '/legacy-category/:cat/',
            'title' => 'Legacy category :cat'
          }
        }
      },
      files: files
    ) do |site,|
      news_page = page_by_url(site, '/legacy-category/news/')
      updates_page = page_by_url(site, '/legacy-category/updates/')

      expect(news_page).not_to be_nil
      expect(updates_page).not_to be_nil
      expect(news_page.data.fetch('title')).to eq('Legacy category news')
      expect(news_page.data.fetch('autogen')).to eq('jekyll-paginate-v2')
      expect(news_page.data.fetch('autopages').fetch('key')).to eq('category')
      expect(news_page.data.fetch('category')).to eq('news')
      expect(paginator_item_titles(news_page)).to eq(['Post 01'])
    end
  end

  it 'migrates legacy collections autopages config into collection index pages' do
    files = jekyll_merge(
      post_files(1),
      collection_document('products', 'widget.md', { 'layout' => 'listing', 'title' => 'Widget', 'permalink' => '/products/widget/' }, 'Widget')
    )

    jekyll_build(
      default_site,
      config: {
        'pagination' => {
          'compatibility' => 'v2'
        },
        'autopages' => {
          'enabled' => true,
          'collections' => {
            'enabled' => true
          }
        }
      },
      files: files
    ) do |site,|
      posts_page = page_by_url(site, '/collection/posts/')
      products_page = page_by_url(site, '/collection/products/')

      expect(posts_page).not_to be_nil
      expect(products_page).not_to be_nil
      expect(posts_page.data.fetch('autopages').fetch('key')).to eq('collection')
      expect(products_page.data.fetch('autopages').fetch('value')).to eq('products')
      expect(posts_page.data).not_to have_key('collection')
      expect(paginator_item_titles(posts_page)).to eq(['Post 01'])
      expect(paginator_item_titles(products_page)).to eq(['Widget'])
    end
  end
end
