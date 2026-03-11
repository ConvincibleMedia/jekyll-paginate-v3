# frozen_string_literal: true

RSpec.describe 'Pagination integration: grouped template behaviour' do
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
								'group' => [
									{
										'on' => 'size',
										'size' => {
											'start' => 0,
											'step' => 20
										}
									}
								],
								'items' => 'posts',
								'frontmatter' => {
									'layout' => 'autopage_category',
									'permalink' => '/size/:size/',
									'title' => 'Size up to :size'
								},
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

	it 'supports datetime grouped indexes with calendar month sizes' do
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
								'group' => [
									{
										'on' => 'published_on',
										'size' => {
											'start' => '2026-12-12',
											'step' => 'month(2)'
										}
									}
								],
								'items' => 'posts',
								'frontmatter' => {
									'layout' => 'autopage_category',
									'permalink' => '/published/:published_on/',
									'title' => 'Published through :published_on'
								},
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

	it 'supports multi-level grouped sets with mixed simple and ranged entries' do
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
								'group' => [
									{ 'on' => 'category' },
									{ 'on' => 'size', 'size' => 100 },
									{ 'on' => 'published_on', 'size' => 'year' }
								],
								'items' => 'posts',
								'frontmatter' => {
									'layout' => 'autopage_category',
									'permalink' => '/combo/:category/:size/:published_on/',
									'title' => ':category :size :published_on'
								},
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
			expect(normalise_url_for_match(paginator_group_reference(target_page, 'previous').fetch('page').url)).to eq('/combo/cat/200/2027-01-01')
			expect(normalise_url_for_match(paginator_group_reference(target_page, 'prev').fetch('page').url)).to eq('/combo/cat/200/2027-01-01')
		end
	end

	it 'treats one-part grouped permalink as page2+ permalink for generated templates' do
		files = post_files(2) { { 'category' => 'news' } }

		jekyll_build(
			default_site,
			config: {
				'pagination' => {
					'enabled' => true,
					'templates' => {
						'generate' => [
							{
								'group' => 'category',
								'items' => 'posts',
								'frontmatter' => {
									'layout' => 'autopage_category',
									'permalink' => '/archive/:category/',
									'title' => 'Listing :category'
								},
								'per_page' => 1,
								'permalink' => 'slice/:num',
								'title' => ':title / :category / :num'
							}
						]
					}
				}
			},
			files: files
		) do |site,|
			first_page = page_by_url(site, '/archive/news/')
			second_page = page_by_url(site, '/archive/news/slice/2/')

			expect(first_page).not_to be_nil
			expect(second_page).not_to be_nil
			expect(second_page.data.fetch('title')).to eq('Listing news / news / 2')
			expect(paginator_item_titles(second_page)).to eq(['Post 01'])
		end
	end
end
