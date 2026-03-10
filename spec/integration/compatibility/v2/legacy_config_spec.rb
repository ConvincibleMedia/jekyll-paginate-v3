# frozen_string_literal: true

RSpec.describe 'Pagination integration: v2 legacy configuration' do
	it 'migrates legacy template shortcuts and exposes v2 payload aliases' do
		files = jekyll_files do
			file 'index.md' do
				frontmatter(
					pagination_template_frontmatter(
						{
							'title' => 'Shop',
							'permalink' => '/shop/',
							'pagination' => {
								'enabled' => true,
								'items' => 'products',
								'category' => 'featured',
								'per_page' => 1,
								'sort' => 'title asc'
							}
						}
					)
				)
				contents('Template content')
			end

			folder '_products' do
				file 'a.md' do
					frontmatter('layout' => 'listing', 'title' => 'Alpha', 'category' => 'featured', 'permalink' => '/products/alpha/')
					contents('Alpha')
				end

				file 'b.md' do
					frontmatter('layout' => 'listing', 'title' => 'Beta', 'category' => 'featured', 'permalink' => '/products/beta/')
					contents('Beta')
				end

				file 'c.md' do
					frontmatter('layout' => 'listing', 'title' => 'Gamma', 'category' => 'standard', 'permalink' => '/products/gamma/')
					contents('Gamma')
				end
			end
		end

		jekyll_build(
			default_site,
			config: {
				'pagination' => {
					'enabled' => true,
					'compatibility' => 'v2'
				}
			},
			files: files
		) do |site,|
			first_page = page_by_url(site, '/shop/')
			second_page = page_by_url(site, '/shop/page/2/')

			expect(first_page).not_to be_nil
			expect(second_page).not_to be_nil
			expect(paginator_item_titles(first_page)).to eq(['Alpha'])
			expect(paginator_item_titles(second_page)).to eq(['Beta'])
			expect(paginator_payload(first_page)).to include('posts', 'total_posts')
			expect(first_page.data.fetch('autogen')).to eq('jekyll-paginate-v2')
		end
	end

	it 'supports a complex v2 legacy template configuration without requiring v3-only keys' do
		files = jekyll_merge(
			jekyll_files do
				folder '_products' do
					file 'alpha.md' do
						frontmatter(
							'layout' => 'listing',
							'title' => 'Alpha',
							'permalink' => '/products/alpha/',
							'category' => 'featured',
							'tags' => ['sale'],
							'locale' => 'en_GB',
							'details' => { 'priority' => 90 }
						)
						contents('Alpha')
					end

					file 'beta.md' do
						frontmatter(
							'layout' => 'listing',
							'title' => 'Beta',
							'permalink' => '/products/beta/',
							'category' => 'featured',
							'tags' => ['sale', 'featured'],
							'locale' => 'en_GB',
							'details' => { 'priority' => 80 }
						)
						contents('Beta')
					end

					file 'gamma.md' do
						frontmatter(
							'layout' => 'listing',
							'title' => 'Gamma',
							'permalink' => '/products/gamma/',
							'category' => 'featured',
							'tags' => 'sale,flash',
							'locale' => 'en_GB',
							'details' => { 'priority' => 70 }
						)
						contents('Gamma')
					end

					file 'delta.md' do
						frontmatter(
							'layout' => 'listing',
							'title' => 'Delta',
							'permalink' => '/products/delta/',
							'category' => 'featured',
							'tags' => ['sale'],
							'locale' => 'en_GB',
							'details' => { 'priority' => 60 }
						)
						contents('Delta')
					end

					file 'epsilon.md' do
						frontmatter(
							'layout' => 'listing',
							'title' => 'Epsilon',
							'permalink' => '/products/epsilon/',
							'category' => 'featured',
							'tags' => ['sale'],
							'locale' => 'en_GB',
							'details' => { 'priority' => 50 },
							'hidden' => true
						)
						contents('Epsilon')
					end

					file 'zeta.md' do
						frontmatter(
							'layout' => 'listing',
							'title' => 'Zeta',
							'permalink' => '/products/zeta/',
							'category' => 'featured',
							'tags' => ['sale'],
							'locale' => 'fr_FR',
							'details' => { 'priority' => 95 }
						)
						contents('Zeta')
					end

					file 'eta.md' do
						frontmatter(
							'layout' => 'listing',
							'title' => 'Eta',
							'permalink' => '/products/eta/',
							'category' => 'standard',
							'tags' => ['sale'],
							'locale' => 'en_GB',
							'details' => { 'priority' => 85 }
						)
						contents('Eta')
					end

					file 'theta.md' do
						frontmatter(
							'layout' => 'listing',
							'title' => 'Theta',
							'permalink' => '/products/theta/',
							'category' => 'featured',
							'tags' => ['clearance'],
							'locale' => 'en_GB',
							'details' => { 'priority' => 75 }
						)
						contents('Theta')
					end

					file 'iota.md' do
						frontmatter(
							'layout' => 'listing',
							'title' => 'Iota',
							'permalink' => '/products/iota/',
							'category' => 'featured',
							'tags' => ['sale'],
							'locale' => 'en_GB',
							'details' => { 'priority' => 40 }
						)
						contents('Iota')
					end
				end
			end,
			jekyll_files do
				file 'shop.md' do
					frontmatter(
						pagination_template_frontmatter(
							{
								'title' => 'Featured Shop',
								'permalink' => '/shop/',
								'pagination' => {
									'enabled' => true,
									'items' => 'products',
									'category' => 'featured',
									'tag' => 'sale',
									'locale' => 'en_GB',
									'sort_field' => 'details:priority',
									'sort_reverse' => true,
									'offset' => 1,
									'per_page' => 2,
									'limit' => 2,
									'trail' => {
										'before' => 1,
										'after' => 1
									},
									'indexpage' => 'feed',
									'extension' => 'json',
									'permalink' => '/slice/:num/',
									'title' => ':title [page :num/:max]'
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
					'compatibility' => 'v2'
				}
			},
			files: files
		) do |site, output_files|
			shop_page_one = page_by_url(site, '/shop/feed.json')
			shop_page_two = page_by_url(site, '/shop/slice/2/feed.json')

			expect(shop_page_one).not_to be_nil
			expect(shop_page_two).not_to be_nil
			expect(page_by_url(site, '/shop/slice/3/feed.json')).to be_nil

			expect(output_files.list).to include('shop/feed.json', 'shop/slice/2/feed.json')

			expect(shop_page_one.data.fetch('title')).to eq('Featured Shop')
			expect(shop_page_two.data.fetch('title')).to eq('Featured Shop [page 2/2]')
			expect(shop_page_one.data.fetch('autogen')).to eq('jekyll-paginate-v2')

			expect(paginator_item_titles(shop_page_one)).to eq(%w[Beta Gamma])
			expect(paginator_item_titles(shop_page_two)).to eq(%w[Delta Iota])

			selected_titles = paginator_item_titles(shop_page_one) + paginator_item_titles(shop_page_two)
			expect(selected_titles).not_to include('Alpha', 'Epsilon', 'Eta', 'Theta', 'Zeta')

			page_one_payload = paginator_payload(shop_page_one)
			page_two_payload = paginator_payload(shop_page_two)

			expect(page_one_payload).to include('items', 'total_items', 'posts', 'total_posts')
			expect(page_one_payload.fetch('total_posts')).to eq(4)
			expect(page_one_payload.fetch('next_page_path')).to eq('/shop/slice/2/feed.json')
			expect(page_two_payload.fetch('previous_page_path')).to eq('/shop/feed.json')
			expect(page_two_payload.fetch('first_page_path')).to eq('/shop/feed.json')
			expect(page_two_payload.fetch('last_page_path')).to eq('/shop/slice/2/feed.json')
			expect(paginator_trail_numbers(shop_page_one)).to eq([1, 2])
			expect(paginator_trail_numbers(shop_page_two)).to eq([1, 2])
		end
	end
end
