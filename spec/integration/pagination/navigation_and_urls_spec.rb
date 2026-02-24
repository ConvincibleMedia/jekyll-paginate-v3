# frozen_string_literal: true

RSpec.describe 'Pagination integration: navigation, URLs, and trails' do
  it 'supports custom page2 permalink and title formatting' do
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
                    'permalink' => '/slice/:num/feed.json',
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
      page_two = page_by_url(site, '/articles/slice/2/feed.json')

      expect(page_one).not_to be_nil
      expect(page_two).not_to be_nil

      expect(output_files.list).to include('articles/index.html', 'articles/slice/2/feed.json')
      expect(page_one.data.fetch('title')).to eq('News')
      expect(page_two.data.fetch('title')).to eq('News [page 2/2]')
      expect(paginator_reference_url(page_one, 'next')).to eq('/articles/slice/2/feed.json')
      expect(paginator_reference_url(page_two, 'prev')).to eq('/articles/')
    end
  end

  it 'calculates previous/next/first/last paginator references consistently' do
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

      expect(paginator_reference_number(page_one, 'prev')).to be_nil
      expect(paginator_reference_url(page_one, 'next')).to eq('/page/2/')
      expect(paginator_reference_url(page_two, 'prev')).to eq('/')
      expect(paginator_reference_url(page_two, 'next')).to eq('/page/3/')
      expect(paginator_reference_number(page_three, 'next')).to be_nil
      expect(paginator_reference_url(page_three, 'first')).to eq('/')
      expect(paginator_reference_url(page_three, 'last')).to eq('/page/3/')
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

