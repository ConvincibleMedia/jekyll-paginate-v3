# frozen_string_literal: true

RSpec.describe 'Pagination integration: generated template edge cases' do
  it 'silently skips generated templates targeting unknown collections when silent is enabled' do
    files = post_files(1) { { 'category' => 'news' } }

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
                'location' => 'unknown_collection',
                'permalink' => '/topics/:category/',
                'title' => 'Topic :category',
                'silent' => true
              }
            ]
          }
        }
      },
      files: files
    ) do |site,|
      expect(page_by_url(site, '/topics/news/')).to be_nil
      expect(generated_pagination_pages(site)).to eq([])
    end
  end

  it 'raises an explicit error when generate index keys are duplicated' do
    files = post_files(1) { { 'category' => 'news' } }

    expect do
      jekyll_build(
        default_site,
        config: {
          'pagination' => {
            'enabled' => true,
            'templates' => {
              'generate' => [
                {
                  'items' => 'posts',
                  'index' => 'category,category',
                  'layout' => 'autopage_category.html',
                  'permalink' => '/topics/:category/',
                  'title' => 'Topic :category'
                }
              ]
            }
          }
        },
        files: files
      ) do
      end
    end.to raise_error(JekyllTestHarness::SiteBuildError, /duplicate `index` key/)
  end

  it 'raises an explicit error when multi-level group is not keyed by index key' do
    files = post_files(1) { { 'category' => 'news', 'size' => 10 } }

    expect do
      jekyll_build(
        default_site,
        config: {
          'pagination' => {
            'enabled' => true,
            'templates' => {
              'generate' => [
                {
                  'items' => 'posts',
                  'index' => 'category,size',
                  'group' => 100,
                  'layout' => 'autopage_category.html',
                  'permalink' => '/topics/:category/:size/',
                  'title' => 'Topic :category :size'
                }
              ]
            }
          }
        },
        files: files
      ) do
      end
    end.to raise_error(JekyllTestHarness::SiteBuildError, /Multi-level `index` requires `group` to be keyed/)
  end

  it 'treats generate definitions without items as invalid' do
    files = post_files(1) { { 'category' => 'news' } }

    jekyll_build(
      default_site,
      config: {
        'pagination' => {
          'enabled' => true,
          'templates' => {
            'generate' => [
              {
                'index' => 'category',
                'layout' => 'autopage_category.html',
                'permalink' => '/topics/:category/',
                'title' => 'Topic :category'
              }
            ]
          }
        }
      },
      files: files
    ) do |site,|
      expect(page_by_url(site, '/topics/news/')).to be_nil
      expect(generated_pagination_pages(site)).to eq([])
    end
  end

  it 'allows generate definitions without index by creating one non-indexed template' do
    files = post_files(2) do |index|
      index == 1 ? { 'category' => 'news' } : { 'category' => 'docs' }
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
                'layout' => 'autopage_category.html',
                'permalink' => '/topics/all/',
                'title' => 'Topic :category',
                'sort' => 'title asc'
              }
            ]
          }
        }
      },
      files: files
    ) do |site,|
      generated_page = page_by_url(site, '/topics/all/')

      expect(generated_page).not_to be_nil
      expect(page_by_url(site, '/topics/news/')).to be_nil
      expect(page_by_url(site, '/topics/docs/')).to be_nil
      expect(generated_page.data.fetch('title')).to eq('Topic :category')
      expect(paginator_item_titles(generated_page)).to eq(['Post 01', 'Post 02'])
      expect(generated_pagination_pages(site).length).to eq(1)
    end
  end

  it 'treats allow_empty as a no-op for non-collection indexes' do
    files = post_files(2) do |index|
      index == 1 ? { 'category' => 'news' } : { 'category' => 'updates' }
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
                'permalink' => '/category/:category/',
                'title' => 'Category :category',
                'allow_empty' => true
              }
            ]
          }
        }
      },
      files: files
    ) do |site,|
      expect(page_by_url(site, '/category/news/')).not_to be_nil
      expect(page_by_url(site, '/category/updates/')).not_to be_nil
      expect(page_by_url(site, '/category/products/')).to be_nil
    end
  end

  it 'falls back to templates.location when generate location is all or everything' do
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
                'location' => 'everything',
                'layout' => 'autopage_category.html',
                'permalink' => '/collection-index/:category/',
                'title' => 'Collection :category'
              }
            ]
          }
        }
      },
      files: files
    ) do |site,|
      generated_document = document_by_url(site, 'products', '/collection-index/news/')

      expect(generated_document).not_to be_nil
      expect(paginator_item_titles(generated_document)).to eq(['Post 01'])
    end
  end

  it 'uses longest placeholder matches when generated permalink tokens overlap' do
    files = post_files(1) do
      {
        'foo' => 'small',
        'foob' => 'large',
        'bar' => 'tail'
      }
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
                'index' => 'foo,foob,bar',
                'layout' => 'autopage_category.html',
                'permalink' => '/page:foobar:foo:bar/',
                'title' => 'Token test :foobar:foo:bar'
              }
            ]
          }
        }
      },
      files: files
    ) do |site,|
      expect(page_by_url(site, '/pagelargearsmalltail/')).not_to be_nil
      expect(page_by_url(site, '/pagesmallbartail/')).to be_nil
    end
  end
end
