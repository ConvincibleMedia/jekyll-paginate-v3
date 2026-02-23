# frozen_string_literal: true

RSpec.describe 'Pagination integration: compatibility v2' do
  it 'migrates legacy template shortcuts and exposes v2 payload aliases' do
    template_frontmatter = pagination_template_frontmatter(
      {
        'title' => 'Shop',
        'permalink' => '/shop/',
        'pagination' => {
          'enabled' => true,
          'collection' => 'products',
          'category' => 'featured',
          'per_page' => 1,
          'sort' => 'title asc'
        }
      }
    )

    files = jekyll_merge(
      jekyll_files do
        file 'index.md' do
          frontmatter(template_frontmatter)
          contents('Template content')
        end
      end,
      collection_document('products', 'a.md', { 'layout' => 'listing', 'title' => 'Alpha', 'category' => 'featured', 'permalink' => '/products/alpha/' }, 'Alpha')
    )
    files = jekyll_merge(files, collection_document('products', 'b.md', { 'layout' => 'listing', 'title' => 'Beta', 'category' => 'featured', 'permalink' => '/products/beta/' }, 'Beta'))
    files = jekyll_merge(files, collection_document('products', 'c.md', { 'layout' => 'listing', 'title' => 'Gamma', 'category' => 'standard', 'permalink' => '/products/gamma/' }, 'Gamma'))

    jekyll_build(
      default_site,
      config: {
        'pagination' => {
          'enabled' => true,
          'compatibility' => 'v2'
        }
      },
      files: files
    ) do |site,|
      first_page = page_by_url(site, '/shop/')
      second_page = page_by_url(site, '/shop/page/2/')

      expect(first_page).not_to be_nil
      expect(second_page).not_to be_nil
      expect(paginator_item_titles(first_page)).to eq(['Alpha'])
      expect(paginator_item_titles(second_page)).to eq(['Beta'])
      expect(first_page.data.fetch('paginator')).to include('posts', 'total_posts')
      expect(first_page.data.fetch('autogen')).to eq('jekyll-paginate-v2')
    end
  end

  it 'migrates legacy autopages config into generated templates' do
    files = post_files(3) do |index|
      case index
      when 1 then { 'tags' => ['ruby', 'jekyll'] }
      when 2 then { 'tags' => ['ruby'] }
      else { 'tags' => ['tooling'] }
      end
    end

    jekyll_build(
      default_site,
      config: {
        'pagination' => {
          'compatibility' => 'v2'
        },
        'autopages' => {
          'enabled' => true,
          'tags' => {
            'enabled' => true
          }
        }
      },
      files: files
    ) do |site,|
      ruby_tag_page = page_by_url(site, '/tag/ruby/') || page_by_url(site, '/tag/ruby')
      jekyll_tag_page = page_by_url(site, '/tag/jekyll/') || page_by_url(site, '/tag/jekyll')

      expect(ruby_tag_page).not_to be_nil
      expect(jekyll_tag_page).not_to be_nil
      expect(paginator_item_titles(ruby_tag_page)).to eq(['Post 02', 'Post 01'])
      expect(ruby_tag_page.data.fetch('autogen')).to eq('jekyll-paginate-v2')
      expect(ruby_tag_page.data.fetch('autopages').fetch('key')).to eq('tag')
      expect(ruby_tag_page.data.fetch('tag')).to eq('ruby')
    end
  end

  it 'supports legacy token aliases in generated permalinks and titles' do
    files = post_files(2) { { 'category' => 'news' } }

    jekyll_build(
      default_site,
      config: {
        'pagination' => {
          'enabled' => true,
          'compatibility' => 'v2',
          'templates' => {
            'generate' => [
              {
                'items' => 'posts',
                'index' => 'category',
                'layout' => 'autopage_category.html',
                'permalink' => '/legacy/:cat/',
                'title' => 'Legacy :cat',
                'sort' => 'title asc'
              }
            ]
          }
        }
      },
      files: files
    ) do |site,|
      legacy_page = page_by_url(site, '/legacy/news/')
      expect(legacy_page).not_to be_nil
      expect(legacy_page.data.fetch('title')).to eq('Legacy news')
      expect(paginator_item_titles(legacy_page)).to eq(['Post 01', 'Post 02'])
    end
  end
end

