# frozen_string_literal: true

RSpec.describe 'Pagination integration: generated template edge cases' do
	it 'skips generated templates targeting unknown collection destinations' do
		files = post_files(1) { { 'category' => 'news' } }

		jekyll_build(
			default_site,
			config: {
				'pagination' => {
					'enabled' => true,
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
