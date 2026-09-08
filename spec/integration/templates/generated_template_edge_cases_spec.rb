# frozen_string_literal: true

RSpec.describe 'Pagination integration: generated template edge cases' do
	it 'consumes generated grouped templates with no represented values without affecting other templates' do
		files = post_files(2) { { 'category' => 'news' } }
		logger = Jekyll.logger
		allow(Jekyll).to receive(:logger).and_return(logger)
		allow(logger).to receive(:info)
		allow(logger).to receive(:warn)
		allow(logger).to receive(:error)

		jekyll_build(
			default_site,
			config: {
				'pagination' => {
					'enabled' => true,
					'templates' => {
						'location' => ['products', 'pages'],
						'generate' => [
							{
								'collection' => 'products',
								'items' => 'posts',
								'group' => 'metadata.environment',
								'per_page' => 1,
								'frontmatter' => {
									'layout' => 'listing',
									'permalink' => '/products/environment/:metadata.environment/',
									'title' => 'Environment :metadata.environment'
								}
							},
							{
								'items' => 'posts',
								'group' => 'category',
								'frontmatter' => {
									'layout' => 'listing',
									'permalink' => '/products/category/:category/',
									'title' => 'Category :category'
								}
							},
							{
								'items' => 'posts',
								'frontmatter' => {
									'layout' => 'listing',
									'permalink' => '/products/all/',
									'title' => 'All products'
								}
							}
						]
					}
				}
			},
			files: files
		) do |site, built_files|
			product_documents = site.collections.fetch('products').docs
			product_output_files = built_files.list('products')

			expect(product_documents.none? { |document| document.url.to_s.include?(':metadata.environment') }).to be(true)
			expect(product_documents.none? { |document| normalise_url_for_match(document.url).start_with?('/products/environment') }).to be(true)
			expect(product_output_files.none? { |path| path.include?(':metadata.environment') }).to be(true)
			expect(product_output_files.none? { |path| path.start_with?('products/environment/') }).to be(true)
			expect(page_by_url(site, '/products/category/news/')).not_to be_nil
			expect(page_by_url(site, '/products/all/')).not_to be_nil
		end

		expect(logger).to have_received(:info).with(
			'Pagination:',
			a_string_matching(/products:.*1 template.*0 indexes.*0 total items/)
		)
	end

	it 'skips generated templates targeting unknown collection destinations' do
		files = post_files(1) { { 'category' => 'news' } }

		jekyll_build(
			default_site,
			config: {
				'pagination' => {
					'enabled' => true,
					'items' => 'posts',
					'templates' => {
						'generate' => [
							{
								'collection' => 'unknown_collection',
								'group' => 'category',
								'frontmatter' => {
									'layout' => 'autopage_category',
									'permalink' => '/topics/:category/',
									'title' => 'Topic :category'
								}
							}
						]
					}
				}
			},
			files: files
		) do |site,|
			expect(page_by_url(site, '/topics/news/')).to be_nil
			expect(generated_pagination_pages(site)).to eq([])
		end
	end

	it 'treats empty generate definitions as invalid' do
		files = post_files(1) { { 'category' => 'news' } }

		jekyll_build(
			default_site,
			config: {
				'pagination' => {
					'enabled' => true,
					'items' => 'posts',
					'templates' => {
						'generate' => [
							{}
						]
					}
				}
			},
			files: files
		) do |site,|
			expect(generated_pagination_pages(site)).to eq([])
		end
	end

	it 'allows generate definitions to rely on site-level pagination defaults' do
		files = post_files(2) do |index|
			index == 1 ? { 'category' => 'news' } : { 'category' => 'docs' }
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
								'group' => 'category',
								'frontmatter' => {
									'layout' => 'autopage_category',
									'permalink' => '/topics/:category/',
									'title' => 'Topic :category'
								}
							}
						]
					}
				}
			},
			files: files
		) do |site,|
			expect(page_by_url(site, '/topics/news/')).not_to be_nil
			expect(page_by_url(site, '/topics/docs/')).not_to be_nil
		end
	end

	it 'treats generated template self/shadow/clone collection modes as pages' do
		files = post_files(1) { { 'category' => 'news' } }

		jekyll_build(
			default_site,
			config: {
				'pagination' => {
					'enabled' => true,
					'items' => 'posts',
					'templates' => {
						'generate' => [
							{
								'collection' => 'self,clone',
								'group' => 'category',
								'frontmatter' => {
									'layout' => 'autopage_category',
									'permalink' => '/collection-index/:category/',
									'title' => 'Collection :category'
								}
							}
						]
					}
				}
			},
			files: files
		) do |site,|
			generated_document = document_by_url(site, 'products', '/collection-index/news/')
			generated_page = page_by_url(site, '/collection-index/news/')

			expect(generated_document).to be_nil
			expect(generated_page).not_to be_nil
			expect(paginator_item_titles(generated_page)).to eq(['Post 01'])
		end
	end

	it 'uses longest placeholder matches when grouped permalink tokens overlap' do
		files = post_files(1) do
			{
				'foo' => 'small',
				'foob' => 'large',
				'bar' => 'tail'
			}
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
								'group' => ['foo', 'foob', 'bar'],
								'frontmatter' => {
									'layout' => 'autopage_category',
									'permalink' => '/page:foobar:foo:bar/',
									'title' => 'Token test :foobar:foo:bar'
								}
							}
						]
					}
				}
			},
			files: files
		) do |site,|
			expect(page_by_url(site, '/pagelargearsmalltail/')).not_to be_nil
			expect(page_by_url(site, '/pagesmallbartail/')).to be_nil
		end
	end
end
