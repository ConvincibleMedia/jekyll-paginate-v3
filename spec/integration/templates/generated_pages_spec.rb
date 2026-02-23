# frozen_string_literal: true

RSpec.describe 'Pagination integration: generated templates in pages' do
  it 'builds generated templates from index values and paginates them' do
    files = post_files(3) do |index|
      case index
      when 1 then { 'category' => 'news' }
      when 2 then { 'category' => 'news' }
      else { 'category' => 'docs' }
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
                'permalink' => '/topics/:category/',
                'title' => 'Topic :category',
                'per_page' => 1,
                'sort' => 'title asc'
              }
            ]
          }
        }
      },
      files: files
    ) do |site,|
      news_page_one = page_by_url(site, '/topics/news/')
      news_page_two = page_by_url(site, '/topics/news/page/2/')
      docs_page = page_by_url(site, '/topics/docs/')

      expect(news_page_one).not_to be_nil
      expect(news_page_two).not_to be_nil
      expect(docs_page).not_to be_nil

      expect(paginator_item_titles(news_page_one)).to eq(['Post 01'])
      expect(paginator_item_titles(news_page_two)).to eq(['Post 02'])
      expect(docs_page.data.dig('pagination', 'generated')).to eq(true)
    end
  end

  it 'supports multi-level index keys and precedence of explicit filters over shorthand filter' do
    files = post_files(4) do |index|
      case index
      when 1 then { 'category' => 'Data Science', 'author' => { 'name' => 'Ada Lovelace' } }
      when 2 then { 'category' => 'Data Science', 'author' => { 'name' => 'Alan Turing' } }
      when 3 then { 'category' => 'Math', 'author' => { 'name' => 'Ada Lovelace' } }
      else { 'category' => 'Data Science', 'author' => { 'name' => 'Grace Hopper' } }
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
                'index' => 'category, author.name',
                'layout' => 'autopage_tags.html',
                'permalink' => '/catalogue/:category/:author.name/',
                'title' => ':category by :author.name',
                'filter' => '/^a/i',
                'filters' => {
                  'category' => 'Data Science'
                },
                'sort' => 'title asc'
              }
            ]
          }
        }
      },
      files: files
    ) do |site,|
      ada_page = page_by_url(site, '/catalogue/data-science/ada-lovelace/')
      alan_page = page_by_url(site, '/catalogue/data-science/alan-turing/')
      grace_page = page_by_url(site, '/catalogue/data-science/grace-hopper/')
      math_page = page_by_url(site, '/catalogue/math/ada-lovelace/')

      expect(ada_page).not_to be_nil
      expect(alan_page).not_to be_nil
      expect(grace_page).to be_nil
      expect(math_page).to be_nil
      expect(paginator_item_titles(ada_page)).to eq(['Post 01'])
      expect(paginator_item_titles(alan_page)).to eq(['Post 02'])
    end
  end

  it 'merges generated frontmatter and pagination overrides from definitions' do
    files = post_files(2) { { 'category' => 'guides' } }

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
                'layout' => 'autopage_tags.html',
                'permalink' => '/section/:category/',
                'title' => 'Section :category',
                'frontmatter' => {
                  'section' => 'knowledge-base'
                },
                'per_page' => 1,
                'trail' => {
                  'before' => 1,
                  'after' => 0
                }
              }
            ]
          }
        }
      },
      files: files
    ) do |site,|
      first_page = page_by_url(site, '/section/guides/')
      second_page = page_by_url(site, '/section/guides/page/2/')

      expect(first_page.data.fetch('section')).to eq('knowledge-base')
      expect(first_page.data.fetch('title')).to eq('Section guides')
      expect(paginator_trail_numbers(first_page)).to eq([1, 2])
      expect(paginator_trail_numbers(second_page)).to eq([1, 2])
    end
  end
end

