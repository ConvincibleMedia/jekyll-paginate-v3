# frozen_string_literal: true

RSpec.describe 'Pagination integration: generated templates in collections' do
	it 'creates generated templates as collection documents when collection target is a collection' do
		files = post_files(3) do |index|
			case index
			when 1 then { 'category' => 'news' }
			when 2 then { 'category' => 'news' }
			else { 'category' => 'updates' }
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
								'collection' => 'guides',
								'group' => 'category',
								'frontmatter' => {
									'layout' => 'autopage_category',
									'permalink' => '/guides/:category/',
									'title' => 'Guide :category'
								},
								'per_page' => 1,
								'sort' => 'title asc'
							}
						]
					}
				}
			},
			files: files
		) do |site,|
			news_doc_one = document_by_url(site, 'guides', '/guides/news/')
			news_doc_two = document_by_url(site, 'guides', '/guides/news/2/')
			updates_doc = document_by_url(site, 'guides', '/guides/updates/')

			expect(news_doc_one).not_to be_nil
			expect(news_doc_two).not_to be_nil
			expect(updates_doc).not_to be_nil
			expect(news_doc_one.data.dig('pagination', 'generated')).to eq(true)
			expect(paginator_item_titles(news_doc_one)).to eq(['Post 01'])
			expect(paginator_item_titles(news_doc_two)).to eq(['Post 02'])
		end
	end

	it 'defaults generated template collection target from pagination.collection when omitted' do
		files = post_files(1) { { 'category' => 'news' } }

		jekyll_build(
			default_site,
			config: {
				'pagination' => {
					'enabled' => true,
					'collection' => 'products',
					'items' => 'posts',
					'templates' => {
						'generate' => [
							{
								'group' => 'category',
								'frontmatter' => {
									'layout' => 'autopage_category',
									'permalink' => '/products-index/:category/',
									'title' => 'Products :category'
								}
							}
						]
					}
				}
			},
			files: files
		) do |site,|
			generated_doc = document_by_url(site, 'products', '/products-index/news/')
			expect(generated_doc).not_to be_nil
			expect(paginator_item_titles(generated_doc)).to eq(['Post 01'])
		end
	end

	it 'lets generate definitions override the site-level template collection default' do
		files = post_files(1) { { 'category' => 'news' } }

		jekyll_build(
			default_site,
			config: {
				'pagination' => {
					'enabled' => true,
					'collection' => 'products',
					'items' => 'posts',
					'templates' => {
						'generate' => [
							{
								'collection' => 'guides',
								'group' => 'category',
								'frontmatter' => {
									'layout' => 'autopage_category',
									'permalink' => '/guide-index/:category/',
									'title' => 'Guide :category'
								}
							}
						]
					}
				}
			},
			files: files
		) do |site,|
			expect(document_by_url(site, 'products', '/guide-index/news/')).to be_nil
			expect(document_by_url(site, 'guides', '/guide-index/news/')).not_to be_nil
		end
	end
end
