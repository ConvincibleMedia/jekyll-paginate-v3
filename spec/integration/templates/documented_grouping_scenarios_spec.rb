# frozen_string_literal: true

RSpec.describe 'Pagination integration: documented grouping scenarios' do
	it 'places one item into every group matched by a multi-value key' do
		files = post_files(3) do |index|
			case index
			when 1 then { 'tags' => ['Ruby', 'Jekyll'] }
			when 2 then { 'tags' => ['Jekyll'] }
			else { 'tags' => ['Guides'] }
			end
		end

		jekyll_build(
			default_site,
			config: {
				'pagination' => {
					'enabled' => true,
					'items' => 'posts',
					'templates' => {
						'generate' => [
							{
								'group' => 'tags',
								'frontmatter' => {
									'layout' => 'autopage_tags',
									'permalink' => '/topics/:tags/',
									'title' => 'Topic :tags'
								},
								'sort' => 'title asc'
							}
						]
					}
				}
			},
			files: files
		) do |site,|
			ruby_page = page_by_url(site, '/topics/ruby/')
			jekyll_page = page_by_url(site, '/topics/jekyll/')
			guides_page = page_by_url(site, '/topics/guides/')

			expect(ruby_page).not_to be_nil
			expect(jekyll_page).not_to be_nil
			expect(guides_page).not_to be_nil
			expect(paginator_item_titles(ruby_page)).to eq(['Post 01'])
			expect(paginator_item_titles(jekyll_page)).to eq(['Post 01', 'Post 02'])
			expect(paginator_item_titles(guides_page)).to eq(['Post 03'])
		end
	end

	it 'supports documented bunch ranges with empty and open-ended numeric groups' do
		files = post_files(2) do |index|
			case index
			when 1 then { 'title' => 'Compact Item', 'size' => 50 }
			else { 'title' => 'Large Item', 'size' => 250 }
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
									{
										'on' => 'size',
										'bunch' => {
											'start' => 0,
											'step' => 100,
											'total' => 3,
											'empty' => true
										}
									}
								],
								'items' => 'posts',
								'frontmatter' => {
									'layout' => 'autopage_category',
									'permalink' => '/sizes/:size/',
									'title' => 'Size up to :size'
								},
								'sort' => 'size asc'
							}
						]
					}
				}
			},
			files: files
		) do |site,|
			page_100 = page_by_url(site, '/sizes/100/')
			page_200 = page_by_url(site, '/sizes/200/')
			page_300 = page_by_url(site, '/sizes/300/')

			expect(page_100).not_to be_nil
			expect(page_200).not_to be_nil
			expect(page_300).not_to be_nil
			expect(paginator_item_titles(page_100)).to eq(['Compact Item'])
			expect(paginator_item_titles(page_200)).to eq([])
			expect(paginator_item_titles(page_300)).to eq(['Large Item'])
			expect(page_200.data.fetch('title')).to eq('Size up to 200')

			expect(normalise_url_for_match(paginator_group_reference(page_100, 'next').fetch('page').url)).to eq('/sizes/200')
			expect(normalise_url_for_match(paginator_group_reference(page_200, 'next').fetch('page').url)).to eq('/sizes/300')
			expect(paginator_group_reference(page_200, 'current')).to include('num' => 2, 'count' => 0, 'start' => '100', 'end' => '200')
			expect(paginator_group_reference(page_300, 'current')).to include('num' => 3, 'count' => 1, 'start' => '200')
			expect(paginator_group_reference(page_300, 'current')).not_to have_key('end')
		end
	end

	it 'supports documented alphabetic bunches and keeps the other bucket last' do
		files = post_files(3) do |index|
			case index
			when 1 then { 'title' => 'Apple Guide' }
			when 2 then { 'title' => 'Zebra Guide' }
			else { 'title' => '9 Lives Guide' }
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
									{
										'on' => 'title',
										'bunch' => {
											'start' => 'a',
											'step' => 13,
											'other' => '0-9'
										}
									}
								],
								'items' => 'posts',
								'frontmatter' => {
									'layout' => 'autopage_category',
									'permalink' => '/catalogue/:title/',
									'title' => 'Range :title'
								},
								'sort' => 'title desc'
							}
						]
					}
				}
			},
			files: files
		) do |site,|
			page_n = page_by_url(site, '/catalogue/n/')
			page_a = page_by_url(site, '/catalogue/a/')
			page_other = page_by_url(site, '/catalogue/0-9/')

			expect(page_n).not_to be_nil
			expect(page_a).not_to be_nil
			expect(page_other).not_to be_nil
			expect(paginator_item_titles(page_n)).to eq(['Zebra Guide'])
			expect(paginator_item_titles(page_a)).to eq(['Apple Guide'])
			expect(paginator_item_titles(page_other)).to eq(['9 Lives Guide'])

			expect(paginator_group_reference(page_n, 'current')).to include('num' => 1)
			expect(normalise_url_for_match(paginator_group_reference(page_n, 'next').fetch('page').url)).to eq('/catalogue/a')
			expect(normalise_url_for_match(paginator_group_reference(page_a, 'next').fetch('page').url)).to eq('/catalogue/0-9')
			expect(normalise_url_for_match(paginator_group_reference(page_other, 'previous').fetch('page').url)).to eq('/catalogue/a')
			expect(paginator_group_reference(page_other, 'current')).to include('num' => 3, 'start' => '0-9')
			expect(paginator_group_reference(page_other, 'current')).not_to have_key('end')
		end
	end
end
