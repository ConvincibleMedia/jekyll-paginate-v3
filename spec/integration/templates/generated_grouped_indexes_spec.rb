# frozen_string_literal: true

RSpec.describe 'Pagination integration: grouped generated indexes' do
  it 'generates numeric grouped indexes and exposes grouped-set navigation ordered by sort direction' do
    sizes = [89, 67, 34, 23, 12]
    files = post_files(5) do |index|
      size = sizes[index - 1]
      {
        'title' => "Item #{size}",
        'size' => size
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
                'index' => 'size',
                'group' => {
                  'start' => 0,
                  'step' => 20
                },
                'layout' => 'autopage_category.html',
                'permalink' => '/size/:size/',
                'title' => 'Size up to :size',
                'sort' => 'size desc'
              }
            ]
          }
        }
      },
      files: files
    ) do |site,|
      page_100 = page_by_url(site, '/size/100/')
      page_80 = page_by_url(site, '/size/80/')
      page_40 = page_by_url(site, '/size/40/')
      page_20 = page_by_url(site, '/size/20/')

      expect(page_100).not_to be_nil
      expect(page_80).not_to be_nil
      expect(page_40).not_to be_nil
      expect(page_20).not_to be_nil
      expect(page_by_url(site, '/size/60/')).to be_nil

      expect(paginator_item_titles(page_100)).to eq(['Item 89'])
      expect(paginator_item_titles(page_40)).to eq(['Item 34', 'Item 23'])

      current_group = paginator_group_reference(page_100, 'current')
      next_group = paginator_group_reference(page_100, 'next')
      last_group = paginator_group_reference(page_100, 'last')
      groups_payload = paginator_groups_payload(page_100)

      expect(current_group).to include('num' => 1, 'count' => 1, 'start' => '80', 'end' => '100')
      expect(current_group['page']).to be_nil
      expect(next_group.fetch('num')).to eq(2)
      expect(normalise_url_for_match(next_group.fetch('page').url)).to eq('/size/80')
      expect(last_group).to include('num' => 4, 'start' => '0', 'end' => '20')
      expect(groups_payload.length).to eq(1)
      expect(groups_payload.first.fetch('key')).to eq('size')
      expect(paginator_group_payload(page_100).fetch('key')).to eq(groups_payload.last.fetch('key'))
    end
  end

  it 'supports datetime grouped indexes with calendar month steps' do
    files = post_files(3) do |index|
      published_on = case index
                     when 1 then '2026-12-20'
                     when 2 then '2027-01-10'
                     else '2027-03-01'
                     end

      {
        'title' => "Published #{index}",
        'published_on' => published_on
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
                'index' => 'published_on',
                'group' => {
                  'start' => '2026-12-12',
                  'step' => 'month(2)'
                },
                'layout' => 'autopage_category.html',
                'permalink' => '/published/:published_on/',
                'title' => 'Published through :published_on',
                'sort' => 'published_on asc'
              }
            ]
          }
        }
      },
      files: files
    ) do |site,|
      first_group_page = page_by_url(site, '/published/2027-02-12/')
      second_group_page = page_by_url(site, '/published/2027-04-12/')

      expect(first_group_page).not_to be_nil
      expect(second_group_page).not_to be_nil
      expect(first_group_page.data.fetch('title')).to include('2027-02-12')
      expect(paginator_item_titles(first_group_page)).to eq(['Published 1', 'Published 2'])
      expect(paginator_item_titles(second_group_page)).to eq(['Published 3'])

      first_group_payload = paginator_group_reference(first_group_page, 'current')
      expect(first_group_payload.fetch('start')).to include('2026-12-12')
      expect(first_group_payload.fetch('end')).to include('2027-02-12')
    end
  end

  it 'supports alphabetic grouped indexes and places other groups last' do
    files = post_files(4) do |index|
      topic = case index
              when 1 then 'aardvark'
              when 2 then 'abacus'
              when 3 then 'acorn'
              else '9-lives'
              end

      {
        'title' => "Topic #{index}",
        'topic' => topic
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
                'index' => 'topic',
                'group' => {
                  'start' => 'aa',
                  'step' => 2,
                  'other' => '0-9'
                },
                'layout' => 'autopage_category.html',
                'permalink' => '/alpha/:topic/',
                'title' => 'Topic range :topic',
                'sort' => 'topic asc'
              }
            ]
          }
        }
      },
      files: files
    ) do |site,|
      aa_group_page = page_by_url(site, '/alpha/aa/')
      ac_group_page = page_by_url(site, '/alpha/ac/')
      other_group_page = page_by_url(site, '/alpha/0-9/')

      expect(aa_group_page).not_to be_nil
      expect(ac_group_page).not_to be_nil
      expect(other_group_page).not_to be_nil

      expect(paginator_item_titles(aa_group_page)).to eq(['Topic 1', 'Topic 2'])
      expect(paginator_item_titles(ac_group_page)).to eq(['Topic 3'])
      expect(paginator_item_titles(other_group_page)).to eq(['Topic 4'])

      group_last = paginator_group_reference(aa_group_page, 'last')
      expect(group_last).to include('num' => 3, 'start' => '0-9')
      expect(group_last).not_to have_key('end')
    end
  end

  it 'supports multi-level indexed grouping keyed by index key with shorthand values' do
    files = post_files(4) do |index|
      case index
      when 1 then { 'category' => 'cat', 'size' => 50, 'published_on' => '2026-05-10' }
      when 2 then { 'category' => 'cat', 'size' => 150, 'published_on' => '2026-07-01' }
      when 3 then { 'category' => 'cat', 'size' => 150, 'published_on' => '2027-02-01' }
      else { 'category' => 'dog', 'size' => 70, 'published_on' => '2026-06-01' }
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
                'index' => 'category,size,published_on',
                'group' => {
                  'size' => 100,
                  'published_on' => 'year'
                },
                'layout' => 'autopage_category.html',
                'permalink' => '/combo/:category/:size/:published_on/',
                'title' => ':category :size :published_on',
                'sort' => ['category asc', 'size asc', 'published_on asc']
              }
            ]
          }
        }
      },
      files: files
    ) do |site,|
      target_page = page_by_url(site, '/combo/cat/200/2028-01-01/')
      previous_year_page = page_by_url(site, '/combo/cat/200/2027-01-01/')

      expect(target_page).not_to be_nil
      expect(previous_year_page).not_to be_nil
      expect(paginator_item_titles(target_page)).to eq(['Post 03'])

      groups_payload = paginator_groups_payload(target_page)
      expect(groups_payload.map { |entry| entry.fetch('key') }).to eq(%w[category size published_on])
      expect(paginator_group_payload(target_page).fetch('key')).to eq('published_on')
      expect(paginator_group_reference(target_page, 'current')).to include('num' => 2)
      expect(normalise_url_for_match(paginator_group_reference(target_page, 'prev').fetch('page').url)).to eq('/combo/cat/200/2027-01-01')
    end
  end

  it 'exposes paginator.groups for non-range indexed generated templates' do
    files = post_files(4) do |index|
      case index
      when 1 then { 'category' => 'docs', 'author' => { 'name' => 'Ada' } }
      when 2 then { 'category' => 'news', 'author' => { 'name' => 'Alice' } }
      when 3 then { 'category' => 'news', 'author' => { 'name' => 'Bob' } }
      else { 'category' => 'news', 'author' => { 'name' => 'Bob' } }
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
                'index' => 'category,author.name',
                'layout' => 'autopage_category.html',
                'permalink' => '/by/:category/:author.name/',
                'title' => ':category :author.name',
                'sort' => ['category asc', 'author.name asc', 'title asc']
              }
            ]
          }
        }
      },
      files: files
    ) do |site,|
      target_page = page_by_url(site, '/by/news/bob/')
      expect(target_page).not_to be_nil
      expect(paginator_item_titles(target_page)).to eq(['Post 03', 'Post 04'])

      groups_payload = paginator_groups_payload(target_page)
      expect(groups_payload.map { |entry| entry.fetch('key') }).to eq(['category', 'author.name'])
      expect(paginator_group_payload(target_page).fetch('key')).to eq('author.name')
      expect(paginator_group_reference(target_page, 'current')).to include('num' => 2)
      expect(normalise_url_for_match(paginator_group_reference(target_page, 'prev').fetch('page').url)).to eq('/by/news/alice')
    end
  end

  it 'accepts keyed group syntax for single-level indexes' do
    files = post_files(2) do |index|
      index == 1 ? { 'category' => 'news', 'size' => 10 } : { 'category' => 'news', 'size' => 120 }
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
                'index' => 'size',
                'group' => {
                  'size' => 100
                },
                'layout' => 'autopage_category.html',
                'permalink' => '/single/:size/',
                'title' => 'Single :size',
                'sort' => 'size asc'
              }
            ]
          }
        }
      },
      files: files
    ) do |site,|
      expect(page_by_url(site, '/single/100/')).not_to be_nil
      expect(page_by_url(site, '/single/200/')).not_to be_nil
    end
  end
end
