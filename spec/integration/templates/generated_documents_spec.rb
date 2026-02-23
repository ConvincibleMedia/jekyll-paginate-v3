# frozen_string_literal: true

RSpec.describe 'Pagination integration: generated templates in collections' do
  it 'creates generated templates as collection documents when location is a collection' do
    files = post_files(3) do |index|
      case index
      when 1 then { 'category' => 'news' }
      when 2 then { 'category' => 'news' }
      else { 'category' => 'updates' }
      end
    end

    jekyll_build(
      default_site,
      config: {
        'pagination' => {
          'enabled' => true,
          'templates' => {
            'generate' => [
              {
                'items' => 'posts',
                'index' => 'category',
                'layout' => 'autopage_category.html',
                'location' => 'guides',
                'permalink' => '/guides/:category/',
                'title' => 'Guide :category',
                'per_page' => 1,
                'sort' => 'title asc'
              }
            ]
          }
        }
      },
      files: files
    ) do |site,|
      news_doc_one = document_by_url(site, 'guides', '/guides/news/')
      news_doc_two = document_by_url(site, 'guides', '/guides/news/page/2/')
      updates_doc = document_by_url(site, 'guides', '/guides/updates/')

      expect(news_doc_one).not_to be_nil
      expect(news_doc_two).not_to be_nil
      expect(updates_doc).not_to be_nil
      expect(news_doc_one.data.dig('pagination', 'generated')).to eq(true)
      expect(paginator_item_titles(news_doc_one)).to eq(['Post 01'])
      expect(paginator_item_titles(news_doc_two)).to eq(['Post 02'])
    end
  end

  it 'supports allow_empty for single-level collection indexes' do
    files = collection_document('products', 'widget.md', { 'layout' => 'listing', 'title' => 'Widget', 'permalink' => '/products/widget/' }, 'Widget')

    jekyll_build(
      default_site,
      config: {
        'pagination' => {
          'enabled' => true,
          'templates' => {
            'generate' => [
              {
                'items' => 'products, notes',
                'index' => 'collection',
                'layout' => 'autopage_collection.html',
                'permalink' => '/collection/:collection/',
                'title' => 'Collection :collection',
                'allow_empty' => true
              }
            ]
          }
        }
      },
      files: files
    ) do |site,|
      products_page = page_by_url(site, '/collection/products/')
      notes_page = page_by_url(site, '/collection/notes/')

      expect(products_page).not_to be_nil
      expect(notes_page).not_to be_nil
      expect(paginator_item_titles(products_page)).to eq(['Widget'])
      expect(paginator_item_titles(notes_page)).to eq([])
      expect(notes_page.data.fetch('paginator').fetch('total_items')).to eq(0)
    end
  end

  it 'defaults generated template location from templates.location when omitted' do
    files = post_files(1) { { 'category' => 'news' } }

    jekyll_build(
      default_site,
      config: {
        'pagination' => {
          'enabled' => true,
          'templates' => {
            'location' => 'products',
            'generate' => [
              {
                'items' => 'posts',
                'index' => 'category',
                'layout' => 'autopage_category.html',
                'permalink' => '/products-index/:category/',
                'title' => 'Products :category'
              }
            ]
          }
        }
      },
      files: files
    ) do |site,|
      generated_doc = document_by_url(site, 'products', '/products-index/news/')
      expect(generated_doc).not_to be_nil
      expect(paginator_item_titles(generated_doc)).to eq(['Post 01'])
    end
  end
end

