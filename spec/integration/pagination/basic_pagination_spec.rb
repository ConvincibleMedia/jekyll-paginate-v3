# frozen_string_literal: true

RSpec.describe 'Pagination integration: core behaviour' do
  it 'paginates a template into generated index pages with paginator payloads' do
    files = jekyll_merge(
      post_files(5),
      jekyll_files do
        file 'index.md' do
          frontmatter(
            pagination_template_frontmatter(
              {
                'title' => 'Home',
                'pagination' => {
                  'enabled' => true,
                  'items' => 'posts',
                  'per_page' => 2,
                  'sort' => 'title asc'
                }
              }
            )
          )
          contents('Template content')
        end
      end
    )

    jekyll_build(default_site, files: files) do |site,|
      generated_pages = generated_pagination_pages(site).sort_by { |page| page.data.fetch('paginator').fetch('page') }
      expect(generated_pages.map(&:url)).to eq(['/', '/page/2/', '/page/3/'])

      expect(paginator_item_titles(generated_pages[0])).to eq(['Post 01', 'Post 02'])
      expect(paginator_item_titles(generated_pages[1])).to eq(['Post 03', 'Post 04'])
      expect(paginator_item_titles(generated_pages[2])).to eq(['Post 05'])

      expect(generated_pages[0].data.fetch('paginator').fetch('next_page_path')).to eq('/page/2/index.html')
      expect(generated_pages[2].data.fetch('paginator').fetch('next_page')).to be_nil
      expect(generated_pages[0].data.dig('pagination', 'template')).to be_nil
      expect(generated_pages[0].data.dig('pagination', 'index')).to eq(true)
    end
  end

  it 'excludes hidden content and pagination templates from resolved items' do
    files = jekyll_merge(
      post_files(3) do |index|
        index == 2 ? { 'hidden' => true } : {}
      end,
      jekyll_files do
        file 'index.md' do
          frontmatter(
            pagination_template_frontmatter(
              {
                'title' => 'Template',
                'pagination' => {
                  'enabled' => true,
                  'items' => 'everything',
                  'sort' => 'title asc',
                  'per_page' => 50
                }
              }
            )
          )
          contents('Template content')
        end

        folder 'docs' do
          file 'visible.md' do
            frontmatter('layout' => 'listing', 'title' => 'Visible Page')
            contents('Visible')
          end

          file 'hidden.md' do
            frontmatter('layout' => 'listing', 'title' => 'Hidden Page', 'hidden' => true)
            contents('Hidden')
          end
        end
      end
    )

    jekyll_build(default_site, files: files) do |site,|
      first_page = page_by_url(site, '/')
      titles = paginator_item_titles(first_page)

      expect(titles).to include('Post 01', 'Post 03', 'Visible Page')
      expect(titles).not_to include('Post 02')
      expect(titles).not_to include('Hidden Page')
      expect(titles).not_to include('Template')
    end
  end

  it 'applies offset and limit after sorting to cap emitted page count' do
    files = jekyll_merge(
      post_files(8),
      jekyll_files do
        file 'index.md' do
          frontmatter(
            pagination_template_frontmatter(
              {
                'pagination' => {
                  'enabled' => true,
                  'items' => 'posts',
                  'sort' => 'title asc',
                  'per_page' => 2,
                  'offset' => 3,
                  'limit' => 2
                }
              }
            )
          )
          contents('Template content')
        end
      end
    )

    jekyll_build(default_site, files: files) do |site,|
      generated_pages = generated_pagination_pages(site).sort_by { |page| page.data.fetch('paginator').fetch('page') }
      expect(generated_pages.map(&:url)).to eq(['/', '/page/2/'])

      expect(paginator_item_titles(generated_pages[0])).to eq(['Post 04', 'Post 05'])
      expect(paginator_item_titles(generated_pages[1])).to eq(['Post 06', 'Post 07'])
      expect(page_by_url(site, '/page/3/')).to be_nil
    end
  end
end

