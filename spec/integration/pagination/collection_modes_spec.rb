# frozen_string_literal: true

RSpec.describe 'Pagination integration: collection target modes' do
	it 'uses default self/shadow mode for collection templates' do
		files = jekyll_merge(
			post_files(3),
			collection_document(
				'products',
				'widgets.md',
				pagination_template_frontmatter(
					{
						'title' => 'Widgets',
						'permalink' => '/products/widgets/',
						'pagination' => {
							'enabled' => true,
							'items' => 'posts',
							'per_page' => 1,
							'sort' => 'title asc'
						}
					}
				),
				'Template content'
			)
		)

		jekyll_build(
			default_site,
			config: {
				'pagination' => {
					'enabled' => true,
					'templates' => {
						'location' => 'products'
					}
				}
			},
			files: files
		) do |site,|
			product_indexes = generated_pagination_documents(site, 'products')
			expect(product_indexes.length).to eq(1)
			expect(normalise_url_for_match(product_indexes.first.url)).to eq('/products/widgets')

			shadow_page = page_by_url(site, '/products/widgets/page/2/')
			expect(shadow_page).not_to be_nil
			expect(shadow_page).to be_a(Jekyll::Page)
			expect(shadow_page.data['collection']).to eq('products')
			expect(shadow_page.collection.label).to eq('products')
			expect(document_by_url(site, 'products', '/products/widgets/page/2/')).to be_nil
		end
	end

	it 'supports explicit pages mode for collection templates' do
		files = jekyll_merge(
			post_files(2),
			collection_document(
				'products',
				'widgets.md',
				pagination_template_frontmatter(
					{
						'title' => 'Widgets',
						'permalink' => '/products/widgets/',
						'pagination' => {
							'enabled' => true,
							'items' => 'posts',
							'collection' => 'pages',
							'per_page' => 1,
							'sort' => 'title asc'
						}
					}
				),
				'Template content'
			)
		)

		jekyll_build(
			default_site,
			config: {
				'pagination' => {
					'enabled' => true,
					'templates' => {
						'location' => 'products'
					}
				}
			},
			files: files
		) do |site,|
			expect(generated_pagination_documents(site, 'products')).to eq([])
			expect(page_by_url(site, '/products/widgets/')).not_to be_nil
			expect(page_by_url(site, '/products/widgets/page/2/')).not_to be_nil
		end
	end

	it 'supports clone mode by creating <collection>_indexes dynamically' do
		files = jekyll_merge(
			post_files(3),
			collection_document(
				'products',
				'widgets.md',
				pagination_template_frontmatter(
					{
						'title' => 'Widgets',
						'permalink' => '/products/widgets/',
						'pagination' => {
							'enabled' => true,
							'items' => 'posts',
							'collection' => 'self,clone',
							'per_page' => 1,
							'sort' => 'title asc'
						}
					}
				),
				'Template content'
			)
		)

		jekyll_build(
			default_site,
			config: {
				'pagination' => {
					'enabled' => true,
					'templates' => {
						'location' => 'products'
					}
				}
			},
			files: files
		) do |site,|
			expect(document_by_url(site, 'products', '/products/widgets/')).not_to be_nil
			expect(document_by_url(site, 'products', '/products/widgets/page/2/')).to be_nil
			expect(site.collections).to have_key('products_indexes')
			expect(document_by_url(site, 'products_indexes', '/products/widgets/page/2/')).not_to be_nil
			expect(document_by_url(site, 'products_indexes', '/products/widgets/page/3/')).not_to be_nil
		end
	end

	it 'supports explicit collection-name targets for all generated pages' do
		files = jekyll_merge(
			post_files(2),
			collection_document(
				'products',
				'widgets.md',
				pagination_template_frontmatter(
					{
						'title' => 'Widgets',
						'permalink' => '/products/widgets/',
						'pagination' => {
							'enabled' => true,
							'items' => 'posts',
							'collection' => 'guides',
							'per_page' => 1,
							'sort' => 'title asc'
						}
					}
				),
				'Template content'
			)
		)

		jekyll_build(
			default_site,
			config: {
				'pagination' => {
					'enabled' => true,
					'templates' => {
						'location' => 'products'
					}
				}
			},
			files: files
		) do |site,|
			expect(generated_pagination_documents(site, 'products')).to eq([])
			expect(document_by_url(site, 'guides', '/products/widgets/')).not_to be_nil
			expect(document_by_url(site, 'guides', '/products/widgets/page/2/')).not_to be_nil
		end
	end

	it 'treats self/shadow/clone as pages when original template is a page' do
		files = jekyll_merge(
			post_files(2),
			jekyll_files do
				file 'index.md' do
					frontmatter(
						pagination_template_frontmatter(
							{
								'title' => 'Home',
								'pagination' => {
									'enabled' => true,
									'items' => 'posts',
									'collection' => 'self,clone',
									'per_page' => 1,
									'sort' => 'title asc'
								}
							}
						)
					)
					contents('Template content')
				end
			end
		)

		jekyll_build(default_site, files: files) do |site,|
			expect(page_by_url(site, '/')).not_to be_nil
			expect(page_by_url(site, '/page/2/')).not_to be_nil
			expect(site.collections).not_to have_key('pages_indexes')
		end
	end
end
