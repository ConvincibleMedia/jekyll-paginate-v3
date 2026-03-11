# frozen_string_literal: true

RSpec.describe 'Pagination integration: generated templates in pages' do
	it 'builds generated templates from grouped values and paginates them' do
		files = post_files(3) do |index|
			case index
			when 1 then { 'category' => 'news' }
			when 2 then { 'category' => 'news' }
			else { 'category' => 'docs' }
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
								'group' => 'category',
								'frontmatter' => {
									'layout' => 'autopage_category',
									'permalink' => '/topics/:category/',
									'title' => 'Topic :category'
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
			news_page_one = page_by_url(site, '/topics/news/')
			news_page_two = page_by_url(site, '/topics/news/2/')
			docs_page = page_by_url(site, '/topics/docs/')

			expect(news_page_one).not_to be_nil
			expect(news_page_two).not_to be_nil
			expect(docs_page).not_to be_nil

			expect(paginator_item_titles(news_page_one)).to eq(['Post 01'])
			expect(paginator_item_titles(news_page_two)).to eq(['Post 02'])
			expect(docs_page.data.dig('pagination', 'generated')).to eq(true)
		end
	end

	it 'supports slugify overrides for grouped placeholder values' do
		files = post_files(1) { { 'category' => 'API Guides' } }

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
								'slugify' => {
									'mode' => 'default',
									'lowercase' => false
								},
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
			cased_slug_page = page_by_url(site, '/topics/API-Guides/')
			lowercase_slug_page = page_by_url(site, '/topics/api-guides/')

			expect(cased_slug_page).not_to be_nil
			expect(lowercase_slug_page).to be_nil
			expect(cased_slug_page.data.fetch('title')).to eq('Topic API-Guides')
			expect(paginator_item_titles(cased_slug_page)).to eq(['Post 01'])
		end
	end

	it 'supports multi-level groups and per-entry group filters' do
		files = post_files(4) do |index|
			case index
			when 1 then { 'category' => 'Data Science', 'author' => { 'name' => 'Ada Lovelace' } }
			when 2 then { 'category' => 'Data Science', 'author' => { 'name' => 'Alan Turing' } }
			when 3 then { 'category' => 'Math', 'author' => { 'name' => 'Ada Lovelace' } }
			else { 'category' => 'Data Science', 'author' => { 'name' => 'Grace Hopper' } }
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
								'group' => [
									{ 'on' => 'category' },
									{ 'on' => 'author.name', 'filter' => '/^a/i' }
								],
								'filters' => {
									'category' => 'Data Science'
								},
								'frontmatter' => {
									'layout' => 'autopage_tags',
									'permalink' => '/catalogue/:category/:author.name/',
									'title' => ':category by :author.name'
								},
								'sort' => 'title asc'
							}
						]
					}
				}
			},
			files: files
		) do |site,|
			ada_page = page_by_url(site, '/catalogue/data-science/ada-lovelace/')
			alan_page = page_by_url(site, '/catalogue/data-science/alan-turing/')
			grace_page = page_by_url(site, '/catalogue/data-science/grace-hopper/')
			math_page = page_by_url(site, '/catalogue/math/ada-lovelace/')

			expect(ada_page).not_to be_nil
			expect(alan_page).not_to be_nil
			expect(grace_page).to be_nil
			expect(math_page).to be_nil
			expect(paginator_item_titles(ada_page)).to eq(['Post 01'])
			expect(paginator_item_titles(alan_page)).to eq(['Post 02'])
		end
	end

	it 'merges generated frontmatter and content over the synthetic template' do
		files = post_files(2) { { 'category' => 'guides' } }

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
									'layout' => 'autopage_tags',
									'permalink' => '/section/:category/',
									'title' => 'Section :category',
									'section' => 'knowledge-base'
								},
								'content' => "Generated body for :category\n",
								'per_page' => 1,
								'trail' => {
									'before' => 1,
									'after' => 0
								}
							}
						]
					}
				}
			},
			files: files
		) do |site, output_files|
			first_page = page_by_url(site, '/section/guides/')
			second_page = page_by_url(site, '/section/guides/2/')

			expect(first_page.data.fetch('section')).to eq('knowledge-base')
			expect(first_page.data.fetch('title')).to eq('Section guides')
			expect(paginator_trail_numbers(first_page)).to eq([1, 2])
			expect(paginator_trail_numbers(second_page)).to eq([1, 2])
			expect(output_files.read('section/guides/index.html')).to include('Generated body for guides')
		end
	end
end
