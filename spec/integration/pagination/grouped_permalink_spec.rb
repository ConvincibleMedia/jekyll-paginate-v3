# frozen_string_literal: true

RSpec.describe 'Pagination integration: grouped permalink behaviour' do
	it 'supports two-part grouped permalinks where part1 sets grouped template routes' do
		files = jekyll_merge(
			post_files(2) do
				{
					'category' => 'news',
					'subcategory' => 'guides'
				}
			end,
			jekyll_files do
				file 'grouped.md' do
					frontmatter(
						pagination_template_frontmatter(
							{
								'layout' => 'listing',
								'permalink' => '/legacy/',
								'title' => 'Grouped Listing',
								'pagination' => {
									'enabled' => true,
									'items' => 'posts',
									'per_page' => 1,
									'group' => 'category,subcategory',
									'permalink' => 'catalogue/:category/:subcategory page/:num'
								}
							}
						)
					)
					contents('Template content')
				end
			end
		)

		jekyll_build(default_site, files: files) do |site,|
			first_page = page_by_url(site, '/legacy/catalogue/news/guides/')
			second_page = page_by_url(site, '/legacy/catalogue/news/guides/page/2/')

			expect(first_page).not_to be_nil
			expect(second_page).not_to be_nil
			expect(page_by_url(site, '/legacy/')).to be_nil
		end
	end

	it 'prepends missing grouped placeholders to part1 in grouping order' do
		files = jekyll_merge(
			post_files(2) do
				{
					'category' => 'news',
					'subcategory' => 'guides'
				}
			end,
			jekyll_files do
				file 'grouped.md' do
					frontmatter(
						pagination_template_frontmatter(
							{
								'layout' => 'listing',
								'permalink' => '/legacy/',
								'title' => 'Grouped Listing',
								'pagination' => {
									'enabled' => true,
									'items' => 'posts',
									'per_page' => 1,
									'group' => 'category,subcategory',
									'permalink' => 'catalogue/:subcategory page/:num'
								}
							}
						)
					)
					contents('Template content')
				end
			end
		)

		jekyll_build(default_site, files: files) do |site,|
			first_page = page_by_url(site, '/legacy/news/catalogue/guides/')
			second_page = page_by_url(site, '/legacy/news/catalogue/guides/page/2/')

			expect(first_page).not_to be_nil
			expect(second_page).not_to be_nil
		end
	end

	it 'implies grouped part1 when only one permalink part is configured on generated templates' do
		files = post_files(2) do
			{
				'category' => 'news',
				'subcategory' => 'guides'
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
								'group' => 'category,subcategory',
								'items' => 'posts',
								'per_page' => 1,
								'permalink' => 'page/:num',
								'frontmatter' => {
									'layout' => 'autopage_category',
									'title' => 'Topic :category/:subcategory'
								}
							}
						]
					}
				}
			},
			files: files
		) do |site,|
			first_page = page_by_url(site, '/news/guides/')
			second_page = page_by_url(site, '/news/guides/page/2/')

			expect(first_page).not_to be_nil
			expect(second_page).not_to be_nil
		end
	end

	it 'uses grouped permalink part1/part2 for generated templates even when frontmatter permalink exists' do
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
								'per_page' => 1,
								'permalink' => '/topics/:category slice/:num',
								'frontmatter' => {
									'layout' => 'autopage_category',
									'permalink' => '/legacy/:category/',
									'title' => 'Topic :category'
								}
							}
						]
					}
				}
			},
			files: files
		) do |site,|
			first_page = page_by_url(site, '/topics/news/')
			second_page = page_by_url(site, '/topics/news/slice/2/')

			expect(first_page).not_to be_nil
			expect(second_page).not_to be_nil
			expect(page_by_url(site, '/legacy/news/')).to be_nil
		end
	end

	it 'resolves grouped part1 relative to template route when part1 is not absolute' do
		files = jekyll_merge(
			post_files(2) { { 'category' => 'shoes' } },
			jekyll_files do
				file 'browse.md' do
					frontmatter(
						pagination_template_frontmatter(
							{
								'layout' => 'listing',
								'permalink' => '/browse/',
								'title' => 'Browse',
								'pagination' => {
									'enabled' => true,
									'items' => 'posts',
									'group' => 'category',
									'per_page' => 1,
									'permalink' => ':category :num'
								}
							}
						)
					)
					contents('Template content')
				end
			end
		)

		jekyll_build(default_site, files: files) do |site,|
			first_page = page_by_url(site, '/browse/shoes/')
			second_page = page_by_url(site, '/browse/shoes/2/')

			expect(first_page).not_to be_nil
			expect(second_page).not_to be_nil
			expect(page_by_url(site, '/shoes/')).to be_nil
		end
	end
end
