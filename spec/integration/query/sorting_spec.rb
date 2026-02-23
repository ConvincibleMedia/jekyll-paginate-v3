# frozen_string_literal: true

RSpec.describe 'Pagination integration: sorting behaviour' do
  it 'supports multi-level sorting with nested fields and empty placement' do
    files = post_files(4) do |index|
      case index
      when 1 then { 'priority' => 2, 'owner' => { 'name' => 'Bob' } }
      when 2 then { 'priority' => 2 }
      when 3 then { 'priority' => 1, 'owner' => { 'name' => 'Ada' } }
      else { 'priority' => 1, 'owner' => { 'name' => 'Zed' } }
      end
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
                  'sort' => [
                    'priority desc',
                    'owner.name asc empty:last',
                    'title asc'
                  ]
                }
              }
            )
          )
          contents('Template content')
        end
      end
    )

    jekyll_build(default_site, files: files) do |site,|
      expect(paginator_item_titles(page_by_url(site, '/'))).to eq(['Post 01', 'Post 02', 'Post 03', 'Post 04'])
    end
  end

  it 'supports sorting by synthetic collection field across collection sources' do
    files = jekyll_merge(
      post_files(1),
      jekyll_files do
        file 'index.md' do
          frontmatter(
            pagination_template_frontmatter(
              {
                'pagination' => {
                  'enabled' => true,
                  'items' => 'all',
                  'sort' => [
                    'collection asc',
                    'title asc'
                  ],
                  'per_page' => 50
                }
              }
            )
          )
          contents('Template content')
        end
      end
    )
    files = jekyll_merge(files, collection_document('products', 'alpha.md', { 'layout' => 'listing', 'title' => 'Alpha Product', 'permalink' => '/products/alpha/' }, 'Alpha'))
    files = jekyll_merge(files, collection_document('products', 'beta.md', { 'layout' => 'listing', 'title' => 'Beta Product', 'permalink' => '/products/beta/' }, 'Beta'))

    jekyll_build(default_site, files: files) do |site,|
      expect(paginator_item_titles(page_by_url(site, '/'))).to eq(['Post 01', 'Alpha Product', 'Beta Product'])
    end
  end

  it 'supports custom split delimiters for sort shorthand strings' do
    files = post_files(3) do |index|
      case index
      when 1 then { 'priority' => 1 }
      when 2 then { 'priority' => 3 }
      else { 'priority' => 2 }
      end
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
                  'sort' => 'priority desc|title asc'
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
          'split' => '|'
        }
      },
      files: files
    ) do |site,|
      expect(paginator_item_titles(page_by_url(site, '/'))).to eq(['Post 02', 'Post 03', 'Post 01'])
    end
  end

  it 'scopes equivalent keys to full nested key paths when sorting' do
    files = post_files(3) do |index|
      case index
      when 1 then { 'product' => { 'tags' => 'b' } }
      when 2 then { 'product' => { 'tag' => 'a' } }
      else { 'product' => { 'tag' => 'c' } }
      end
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
                  'sort' => [
                    'product.tag asc empty:last',
                    'title asc'
                  ]
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
          'equivalents' => [
            %w[tag tags]
          ]
        }
      },
      files: files
    ) do |site,|
      expect(paginator_item_titles(page_by_url(site, '/'))).to eq(['Post 02', 'Post 03', 'Post 01'])
    end

    jekyll_build(
      default_site,
      config: {
        'pagination' => {
          'enabled' => true,
          'equivalents' => [
            %w[tag tags],
            ['product.tag', 'product.tags']
          ]
        }
      },
      files: files
    ) do |site,|
      expect(paginator_item_titles(page_by_url(site, '/'))).to eq(['Post 02', 'Post 01', 'Post 03'])
    end
  end
end

