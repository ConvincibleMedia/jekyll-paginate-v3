# frozen_string_literal: true

RSpec.describe 'Pagination integration: navigation, URLs, and trails' do
  it 'supports custom permalink, index filename, extension, and title formatting' do
    files = jekyll_merge(
      post_files(2),
      jekyll_files do
        folder 'news' do
          file 'index.md' do
            frontmatter(
              pagination_template_frontmatter(
                {
                  'title' => 'News',
                  'permalink' => '/articles/',
                  'pagination' => {
                    'enabled' => true,
                    'items' => 'posts',
                    'sort' => 'title asc',
                    'per_page' => 1,
                    'permalink' => '/slice/:num/',
                    'indexpage' => 'feed',
                    'extension' => 'json',
                    'title' => ':title [page :num/:max]'
                  }
                }
              )
            )
            contents('Template content')
          end
        end
      end
    )

    jekyll_build(default_site, files: files) do |site, output_files|
      page_one = page_by_url(site, '/articles/')
      page_two = page_by_url(site, '/articles/slice/2/')

      expect(page_one).not_to be_nil
      expect(page_two).not_to be_nil

      expect(output_files.list).to include('articles/index.json', 'articles/slice/2/index.json')
      expect(page_one.data.fetch('title')).to eq('News')
      expect(page_two.data.fetch('title')).to eq('News [page 2/2]')
      expect(page_one.data.fetch('paginator').fetch('next_page_path')).to eq('/articles/slice/2/feed.json')
      expect(page_two.data.fetch('paginator').fetch('previous_page_path')).to eq('/articles/feed.json')
    end
  end

  it 'calculates previous/next/first/last paginator paths consistently' do
    files = jekyll_merge(
      post_files(3),
      jekyll_files do
        file 'index.md' do
          frontmatter(
            pagination_template_frontmatter(
              {
                'pagination' => {
                  'enabled' => true,
                  'items' => 'posts',
                  'sort' => 'title asc',
                  'per_page' => 1
                }
              }
            )
          )
          contents('Template content')
        end
      end
    )

    jekyll_build(default_site, files: files) do |site,|
      page_one = page_by_url(site, '/')
      page_two = page_by_url(site, '/page/2/')
      page_three = page_by_url(site, '/page/3/')

      expect(page_one.data.fetch('paginator').fetch('previous_page')).to be_nil
      expect(page_one.data.fetch('paginator').fetch('next_page_path')).to eq('/page/2/index.html')
      expect(page_two.data.fetch('paginator').fetch('previous_page_path')).to eq('/index.html')
      expect(page_two.data.fetch('paginator').fetch('next_page_path')).to eq('/page/3/index.html')
      expect(page_three.data.fetch('paginator').fetch('next_page')).to be_nil
      expect(page_three.data.fetch('paginator').fetch('first_page_path')).to eq('/index.html')
      expect(page_three.data.fetch('paginator').fetch('last_page_path')).to eq('/page/3/index.html')
    end
  end

  it 'assigns a padded page trail window near boundaries' do
    files = jekyll_merge(
      post_files(4),
      jekyll_files do
        file 'index.md' do
          frontmatter(
            pagination_template_frontmatter(
              {
                'pagination' => {
                  'enabled' => true,
                  'items' => 'posts',
                  'sort' => 'title asc',
                  'per_page' => 1,
                  'trail' => {
                    'before' => 1,
                    'after' => 1
                  }
                }
              }
            )
          )
          contents('Template content')
        end
      end
    )

    jekyll_build(default_site, files: files) do |site,|
      page_one = page_by_url(site, '/')
      page_two = page_by_url(site, '/page/2/')
      page_four = page_by_url(site, '/page/4/')

      expect(paginator_trail_numbers(page_one)).to eq([1, 2, 3])
      expect(paginator_trail_numbers(page_two)).to eq([1, 2, 3])
      expect(paginator_trail_numbers(page_four)).to eq([2, 3, 4])
    end
  end
end

