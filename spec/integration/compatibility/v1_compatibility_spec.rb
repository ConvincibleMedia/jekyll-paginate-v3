# frozen_string_literal: true

RSpec.describe 'Pagination integration: compatibility v1' do
  it 'automatically enables v1 compatibility when legacy paginate config is present' do
    files = jekyll_merge(
      post_files(3),
      jekyll_files do
        file 'index.html' do
          frontmatter('layout' => 'listing', 'title' => 'Legacy Home')
          contents('Legacy home')
        end
      end
    )

    jekyll_build(
      default_site,
      config: {
        'paginate' => 2,
        'paginate_path' => '/legacy/page:num/'
      },
      files: files
    ) do |site,|
      first_page = page_by_url(site, '/')
      second_page = page_by_url(site, '/legacy/page2/')

      expect(first_page).not_to be_nil
      expect(second_page).not_to be_nil
      expect(paginator_item_titles(first_page)).to eq(['Post 03', 'Post 02'])
      expect(first_page.data.fetch('paginator')).to include('posts', 'total_posts')
    end
  end

  it 'uses explicit pagination templates in v1 mode when present' do
    files = jekyll_merge(
      post_files(2),
      jekyll_files do
        file 'index.html' do
          frontmatter('layout' => 'listing', 'title' => 'Root Page')
          contents('Root')
        end

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
      end
    )

    jekyll_build(
      default_site,
      config: {
        'pagination' => {
          'enabled' => true,
          'compatibility' => 'v1'
        }
      },
      files: files
    ) do |site,|
      blog_page_one = page_by_url(site, '/blog/')
      blog_page_two = page_by_url(site, '/blog/page/2/')
      root_page = page_by_url(site, '/')

      expect(blog_page_one).not_to be_nil
      expect(blog_page_two).not_to be_nil
      expect(root_page.data['paginator']).to be_nil
      expect(paginator_item_titles(blog_page_one)).to eq(['Post 01'])
      expect(paginator_item_titles(blog_page_two)).to eq(['Post 02'])
    end
  end

  it 'chooses the deepest legacy index candidate in paginate path hierarchy' do
    files = jekyll_merge(
      post_files(2),
      jekyll_files do
        file 'index.html' do
          frontmatter('layout' => 'listing', 'title' => 'Root Index')
          contents('Root index')
        end

        folder 'news' do
          file 'index.html' do
            frontmatter('layout' => 'listing', 'title' => 'News Index')
            contents('News index')
          end

          folder 'archive' do
            file 'index.html' do
              frontmatter('layout' => 'listing', 'title' => 'Archive Index')
              contents('Archive index')
            end
          end
        end
      end
    )

    jekyll_build(
      default_site,
      config: {
        'paginate' => 1,
        'paginate_path' => '/news/archive/page:num/'
      },
      files: files
    ) do |site,|
      archive_first_page = page_by_url(site, '/news/archive/')
      archive_second_page = page_by_url(site, '/news/archive/page2/')
      root_page = page_by_url(site, '/')

      expect(archive_first_page).not_to be_nil
      expect(archive_second_page).not_to be_nil
      expect(root_page.data['paginator']).to be_nil
      expect(paginator_item_titles(archive_first_page)).to eq(['Post 02'])
      expect(paginator_item_titles(archive_second_page)).to eq(['Post 01'])
    end
  end
end

