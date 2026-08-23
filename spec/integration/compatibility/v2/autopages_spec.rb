# frozen_string_literal: true

RSpec.describe 'Pagination integration: v2 autopages migration' do
	it 'migrates a full legacy autopages setup for tags, categories, and collections' do
		files = post_files(4) do |index|
			case index
			when 1 then { 'tags' => ['Ruby Gems', 'Jekyll'], 'category' => 'News' }
			when 2 then { 'tags' => ['Ruby Gems'], 'category' => 'Updates' }
			when 3 then { 'tags' => ['Tooling'], 'category' => 'News' }
			else { 'tags' => ['Guides'], 'category' => 'Guides' }
			end
		end
		files = jekyll_merge(files, collection_document('products', 'widget.md', { 'layout' => 'listing', 'title' => 'Widget', 'permalink' => '/products/widget/' }, 'Widget'))
		files = jekyll_merge(files, collection_document('guides', 'start-here.md', { 'layout' => 'listing', 'title' => 'Start Here', 'permalink' => '/guides/start-here/' }, 'Start Here'))

		jekyll_build(
			default_site,
			config: {
				'pagination' => {
					'compatibility' => 'v2'
				},
				'autopages' => {
					'enabled' => true,
					'tags' => {
						'enabled' => true,
						'layout' => 'autopage_tags.html',
						'permalink' => '/legacy-tag/:tag/',
						'title' => 'Legacy tag :tag'
					},
					'categories' => {
						'enabled' => true,
						'layout' => 'autopage_category.html',
						'permalink' => '/legacy-category/:cat/',
						'title' => 'Legacy category :cat'
					},
					'collections' => {
						'enabled' => true,
						'layout' => 'autopage_collection.html',
						'permalink' => '/legacy-collection/:coll/',
						'title' => 'Legacy collection :coll'
					}
				}
			},
			files: files
		) do |site,|
			ruby_tag_page = page_by_url(site, '/legacy-tag/ruby-gems/')
			news_category_page = page_by_url(site, '/legacy-category/news/')
			posts_collection_page = page_by_url(site, '/legacy-collection/posts/')
			products_collection_page = page_by_url(site, '/legacy-collection/products/')
			guides_collection_page = page_by_url(site, '/legacy-collection/guides/')

			expect(ruby_tag_page).not_to be_nil
			expect(news_category_page).not_to be_nil
			expect(posts_collection_page).not_to be_nil
			expect(products_collection_page).not_to be_nil
			expect(guides_collection_page).not_to be_nil
			expect(page_by_url(site, '/legacy-collection/notes/')).to be_nil

			expect(ruby_tag_page.data.fetch('title')).to eq('Legacy tag Ruby Gems')
			expect(ruby_tag_page.data.fetch('autogen')).to eq('jekyll-paginate-v2')
			expect(ruby_tag_page.data.fetch('autopages')).to include('key' => 'tag', 'value' => 'ruby-gems', 'display_name' => 'Ruby Gems')
			expect(ruby_tag_page.data.fetch('tag')).to eq('ruby-gems')
			expect(paginator_item_titles(ruby_tag_page)).to eq(['Post 02', 'Post 01'])

			expect(news_category_page.data.fetch('title')).to eq('Legacy category News')
			expect(news_category_page.data.fetch('autopages')).to include('key' => 'category', 'value' => 'news', 'display_name' => 'News')
			expect(news_category_page.data.fetch('category')).to eq('news')
			expect(paginator_item_titles(news_category_page)).to eq(['Post 03', 'Post 01'])

			expect(posts_collection_page.data.fetch('title')).to eq('Legacy collection posts')
			expect(posts_collection_page.data.fetch('autopages')).to include('key' => 'collection', 'value' => 'posts', 'display_name' => 'posts')
			expect(posts_collection_page.data).not_to have_key('collection')
			expect(paginator_item_titles(posts_collection_page)).to eq(['Post 04', 'Post 03', 'Post 02', 'Post 01'])

			expect(products_collection_page.data.fetch('autopages')).to include('key' => 'collection', 'value' => 'products')
			expect(guides_collection_page.data.fetch('autopages')).to include('key' => 'collection', 'value' => 'guides')
			expect(paginator_item_titles(products_collection_page)).to eq(['Widget'])
			expect(paginator_item_titles(guides_collection_page)).to eq(['Start Here'])
		end
	end

	it 'migrates only enabled legacy autopages groups' do
		files = jekyll_merge(
			post_files(1) { { 'tags' => ['ruby'], 'category' => 'news' } },
			collection_document('products', 'widget.md', { 'layout' => 'listing', 'title' => 'Widget', 'permalink' => '/products/widget/' }, 'Widget')
		)

		jekyll_build(
			default_site,
			config: {
				'pagination' => {
					'compatibility' => 'v2'
				},
				'autopages' => {
					'enabled' => true,
					'tags' => {
						'enabled' => true
					},
					'categories' => {
						'enabled' => false
					},
					'collections' => {
						'enabled' => true
					}
				}
			},
			files: files
		) do |site,|
			ruby_tag_page = page_by_url(site, '/tag/ruby/') || page_by_url(site, '/tag/ruby')
			posts_collection_page = page_by_url(site, '/collection/posts/')
			products_collection_page = page_by_url(site, '/collection/products/')
			news_category_page = page_by_url(site, '/category/news/') || page_by_url(site, '/category/news')

			expect(ruby_tag_page).not_to be_nil
			expect(posts_collection_page).not_to be_nil
			expect(products_collection_page).not_to be_nil
			expect(news_category_page).to be_nil
			expect(ruby_tag_page.data.fetch('autopages').fetch('key')).to eq('tag')
			expect(posts_collection_page.data.fetch('autopages').fetch('key')).to eq('collection')
		end
	end
end
