# frozen_string_literal: true

RSpec.describe 'Pagination integration: layout inheritance validation' do
	it 'lets a generated grouped template inherit items from its selected nested layout' do
		files = jekyll_merge(
			post_files(1) { { 'category' => 'news' } },
			jekyll_files do
				folder '_layouts' do
					folder 'catalogue' do
						file 'listing.html' do
							frontmatter(
								'layout' => 'default',
								'pagination' => {
									'items' => 'posts'
								}
							)
							contents('{{ content }}')
						end
					end
				end
			end
		)

		jekyll_build(
			default_site,
			config: {
				'pagination' => {
					'enabled' => true,
					'templates' => {
						'generate' => [
							{
								'layout' => 'catalogue/listing',
								'group' => 'category',
								'frontmatter' => {
									'permalink' => '/catalogue/:category/',
									'title' => 'Catalogue :category'
								}
							}
						]
					}
				}
			},
			files: files
		) do |site,|
			page = page_by_url(site, '/catalogue/news/')

			expect(page).not_to be_nil
			expect(page.data.fetch('layout')).to eq('catalogue/listing')
			expect(page.data.dig('pagination', 'items')).to eq('posts')
			expect(paginator_item_titles(page)).to eq(['Post 01'])
		end
	end

	it 'lets an explicit template inherit items from pagination.layout' do
		files = jekyll_merge(
			post_files(1),
			jekyll_files do
				folder '_layouts' do
					folder 'catalogue' do
						file 'listing.html' do
							frontmatter(
								'layout' => 'default',
								'pagination' => {
									'items' => 'posts'
								}
							)
							contents('{{ content }}')
						end
					end
				end

				file 'explicit.md' do
					frontmatter(
						'permalink' => '/explicit/',
						'title' => 'Explicit listing',
						'pagination' => {
							'enabled' => true,
							'layout' => 'catalogue/listing'
						}
					)
					contents('Explicit template')
				end
			end
		)

		jekyll_build(default_site, files: files) do |site,|
			page = page_by_url(site, '/explicit/')

			expect(page).not_to be_nil
			expect(page.data.fetch('layout')).to eq('catalogue/listing')
			expect(page.data.dig('pagination', 'items')).to eq('posts')
			expect(paginator_item_titles(page)).to eq(['Post 01'])
		end
	end

	it 'resolves effective items and pagination config independently for each layout variant' do
		files = jekyll_merge(
			jekyll_merge(
				post_files(1) { { 'category' => 'news' } },
				collection_document('products', 'product.md', { 'title' => 'Product 01', 'category' => 'news' })
			),
			jekyll_files do
				folder '_layouts' do
					file 'variant_posts.html' do
						frontmatter(
							'layout' => 'default',
							'pagination' => {
								'items' => 'posts',
								'permalink' => 'posts/:category/ page/:num'
							}
						)
						contents('{{ content }}')
					end

					file 'variant_products.html' do
						frontmatter(
							'layout' => 'default',
							'pagination' => {
								'items' => 'products',
								'permalink' => 'products/:category/ page/:num'
							}
						)
						contents('{{ content }}')
					end
				end

				file 'variants.md' do
					frontmatter(
						'title' => 'Variants',
						'permalink' => '/variants/',
						'pagination' => {
							'enabled' => true,
							'group' => 'category',
							'layouts' => ['variant_posts', 'variant_products']
						}
					)
					contents('Variant template')
				end
			end
		)

		jekyll_build(default_site, files: files) do |site,|
			posts_page = page_by_url(site, '/variants/posts/news/')
			products_page = page_by_url(site, '/variants/products/news/')

			expect(posts_page).not_to be_nil
			expect(products_page).not_to be_nil
			expect(posts_page.data.fetch('layout')).to eq('variant_posts')
			expect(products_page.data.fetch('layout')).to eq('variant_products')
			expect(posts_page.data.dig('pagination', 'items')).to eq('posts')
			expect(products_page.data.dig('pagination', 'items')).to eq('products')
			expect(paginator_item_titles(posts_page)).to eq(['Post 01'])
			expect(paginator_item_titles(products_page)).to eq(['Product 01'])
		end
	end

	it 'fails clearly when no effective configuration supplies items' do
		files = jekyll_files do
			folder '_layouts' do
				file 'missing_items.html' do
					frontmatter('layout' => 'default')
					contents('{{ content }}')
				end
			end
		end

		expect do
			jekyll_build(
				default_site,
				config: {
					'pagination' => {
						'enabled' => true,
						'templates' => {
							'generate' => [
								{
									'layout' => 'missing_items',
									'frontmatter' => {
										'permalink' => '/missing-items/'
									}
								}
							]
						}
					}
				},
				files: files
			) do |_site,|
			end
		end.to raise_error(JekyllTestHarness::SiteBuildError, /ArgumentError: Template .* does not define `pagination\.items`/)
	end

	it 'preserves direct and global items sources without pagination layout overrides' do
		files = jekyll_merge(
			jekyll_merge(
				post_files(1),
				collection_document('products', 'product.md', { 'title' => 'Product 01' })
			),
			jekyll_files do
				file 'global.md' do
					frontmatter(
						'layout' => 'listing',
						'permalink' => '/global/',
						'pagination' => {
							'enabled' => true
						}
					)
					contents('Global items template')
				end

				file 'direct.md' do
					frontmatter(
						'layout' => 'listing',
						'permalink' => '/direct/',
						'pagination' => {
							'enabled' => true,
							'items' => 'products'
						}
					)
					contents('Direct items template')
				end
			end
		)

		jekyll_build(
			default_site,
			config: {
				'pagination' => {
					'enabled' => true,
					'items' => 'posts'
				}
			},
			files: files
		) do |site,|
			global_page = page_by_url(site, '/global/')
			direct_page = page_by_url(site, '/direct/')

			expect(global_page).not_to be_nil
			expect(direct_page).not_to be_nil
			expect(paginator_item_titles(global_page)).to eq(['Post 01'])
			expect(paginator_item_titles(direct_page)).to eq(['Product 01'])
		end
	end

	it 'rejects sort placeholders that are not exact active group keys even without items' do
		files = jekyll_files do
			file 'empty.md' do
				frontmatter(
					'title' => 'Empty grouping',
					'pagination' => {
						'enabled' => true,
						'items' => 'posts',
						'group' => 'meta.category',
						'sort' => 'details.{{ category }}.rank'
					}
				)
				contents('Empty template')
			end
		end

		expect do
			jekyll_build(default_site, files: files) do |_site,|
			end
		end.to raise_error(JekyllTestHarness::SiteBuildError, /Unknown placeholder 'category'.*meta\.category/)
	end

	it 'rejects mixed placeholder styles within one pagination scalar' do
		files = jekyll_merge(
			post_files(1) { { 'category' => 'news' } },
			jekyll_files do
				file 'mixed-placeholders.md' do
					frontmatter(
						'title' => 'Mixed placeholders',
						'pagination' => {
							'enabled' => true,
							'items' => 'posts',
							'group' => 'category',
							'title' => '{{ category }} page :num'
						}
					)
					contents('Mixed template')
				end
			end
		)

		expect do
			jekyll_build(default_site, files: files) do |_site,|
			end
		end.to raise_error(JekyllTestHarness::SiteBuildError, /Cannot mix canonical/)
	end

	it 'rejects filters on numeric system placeholders' do
		files = jekyll_merge(
			post_files(1),
			jekyll_files do
				file 'filtered-number.md' do
					frontmatter(
						'title' => 'Filtered number',
						'pagination' => {
							'enabled' => true,
							'items' => 'posts',
							'title' => 'Page {{ num | slugify }}'
						}
					)
					contents('Filtered number template')
				end
			end
		)

		expect do
			jekyll_build(default_site, files: files) do |_site,|
			end
		end.to raise_error(JekyllTestHarness::SiteBuildError, /Placeholder 'num' does not accept filters in pagination title/)
	end

	it 'rejects raw group placeholders in permalinks' do
		files = post_files(1) { { 'category' => 'C#' } }

		expect do
			jekyll_build(
				default_site,
				config: {
					'pagination' => {
						'enabled' => true,
						'items' => 'posts',
						'templates' => {
							'generate' => [
								{
									'group' => 'category',
									'frontmatter' => {
										'permalink' => '/languages/{{ category | raw }}/',
										'title' => 'Language {{ category }}'
									}
								}
							]
						}
					}
				},
				files: files
			) do |_site,|
			end
		end.to raise_error(JekyllTestHarness::SiteBuildError, /Placeholder 'category' cannot use the 'raw' filter in grouped template permalink/)
	end

	it 'rejects raw sort interpolation when several group values share one slug' do
		files = post_files(2) do |index|
			{ 'category' => index == 1 ? 'Old Shoes' : 'Old--Shoes' }
		end

		expect do
			jekyll_build(
				default_site,
				config: {
					'pagination' => {
						'enabled' => true,
						'items' => 'posts',
						'templates' => {
							'generate' => [
								{
									'group' => 'category',
									'sort' => 'details.{{ category | raw }}.rank',
									'frontmatter' => {
										'permalink' => '/collision/{{ category }}/',
										'title' => 'Collision'
									}
								}
							]
						}
					}
				},
				files: files
			) do |_site,|
			end
		end.to raise_error(JekyllTestHarness::SiteBuildError, /cannot use its raw representation.*multiple raw values with the same slug/)
	end
end
