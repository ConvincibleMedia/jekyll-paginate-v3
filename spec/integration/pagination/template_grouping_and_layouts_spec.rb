# frozen_string_literal: true

RSpec.describe 'Pagination integration: template grouping and layouts' do
	it 'renders generated grouped and ungrouped templates through nested layout overrides' do
		files = jekyll_merge(
			post_files(2) { { 'category' => 'news' } },
			jekyll_files do
				folder '_layouts' do
					folder 'html' do
						folder 'product' do
							file 'catalogue.html' do
								frontmatter(
									'layout' => 'default',
									'pagination' => {
										'per_page' => 1
									}
								)
								contents('<section id="nested-product-layout">{{ content }}</section>')
							end
						end
					end
				end
			end
		)

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
						'generate' => [
							{
								'items' => 'posts',
								'layouts' => 'html/product/catalogue.html',
								'frontmatter' => {
									'permalink' => '/nested/all/',
									'title' => 'All products'
								},
								'content' => 'Ungrouped products'
							},
							{
								'items' => 'posts',
								'group' => 'category',
								'layouts' => 'html/product/catalogue.html',
								'frontmatter' => {
									'permalink' => '/nested/:category/',
									'title' => 'Products in :category'
								},
								'content' => 'Grouped products'
							}
						]
					}
				}
			},
			files: files
		) do |site, built_files|
			ungrouped_first_page = page_by_url(site, '/nested/all/')
			ungrouped_second_page = page_by_url(site, '/nested/all/2/')
			grouped_first_page = page_by_url(site, '/nested/news/')
			grouped_second_page = page_by_url(site, '/nested/news/2/')

			expect(ungrouped_first_page).not_to be_nil
			expect(ungrouped_second_page).not_to be_nil
			expect(grouped_first_page).not_to be_nil
			expect(grouped_second_page).not_to be_nil
			expect(ungrouped_first_page.data.fetch('layout')).to eq('html/product/catalogue')
			expect(grouped_first_page.data.fetch('layout')).to eq('html/product/catalogue')
			expect(built_files.read('nested/all/index.html')).to include('id="nested-product-layout"')
			expect(built_files.read('nested/news/index.html')).to include('id="nested-product-layout"')
		end

		expect(logger).not_to have_received(:warn).with(anything, a_string_including("Layout 'catalogue' does not exist"))
	end

	it 'duplicates grouped templates across layouts and keeps pagination chains layout-local' do
		files = jekyll_merge(
			post_files(4) { { 'category' => 'news' } },
			jekyll_files do
				file 'catalogue.md' do
					frontmatter(
						pagination_template_frontmatter(
							{
								'layout' => 'listing',
								'permalink' => '/catalogue/:category/',
								'title' => 'Catalogue :category',
								'pagination' => {
									'enabled' => true,
									'items' => 'posts',
									'per_page' => 2,
									'sort' => 'title asc',
									'group' => 'category',
									'layouts' => 'autopage_category,autopage_tags'
								}
							}
						)
					)
					contents('Template content')
				end
			end
		)

		jekyll_build(default_site, files: files) do |site,|
			category_layout_pages = generated_pagination_pages(site).select { |page| page.data['layout'] == 'autopage_category' }.sort_by { |page| paginator_index_number(page) }
			tag_layout_pages = generated_pagination_pages(site).select { |page| page.data['layout'] == 'autopage_tags' }.sort_by { |page| paginator_index_number(page) }

			expect(category_layout_pages.length).to eq(2)
			expect(tag_layout_pages.length).to eq(2)
			expect(paginator_item_titles(category_layout_pages.first)).to eq(['Post 01', 'Post 02'])
			expect(paginator_item_titles(tag_layout_pages.first)).to eq(['Post 01', 'Post 02'])

			category_next_reference = paginator_payload(category_layout_pages.first).fetch('next')
			tag_next_reference = paginator_payload(tag_layout_pages.first).fetch('next')
			category_next_page = category_next_reference.respond_to?(:page) ? category_next_reference.page : category_next_reference['page']
			tag_next_page = tag_next_reference.respond_to?(:page) ? tag_next_reference.page : tag_next_reference['page']

			expect(category_next_page.data.fetch('layout')).to eq('autopage_category')
			expect(tag_next_page.data.fetch('layout')).to eq('autopage_tags')
		end
	end

	it 'treats one-part grouped permalink as page2+ permalink while template permalink stays grouped base' do
		files = jekyll_merge(
			post_files(2) { { 'category' => 'news' } },
			jekyll_files do
				file 'archive.md' do
					frontmatter(
						pagination_template_frontmatter(
							{
								'layout' => 'listing',
								'permalink' => '/archive/:category/',
								'title' => 'Archive :category',
								'pagination' => {
									'enabled' => true,
									'items' => 'posts',
									'per_page' => 1,
									'group' => 'category',
									'permalink' => 'slice/:num',
									'title' => ':title / :category / :num'
								}
							}
						)
					)
					contents('Template content')
				end
			end
		)

		jekyll_build(default_site, files: files) do |site,|
			first_page = page_by_url(site, '/archive/news/')
			second_page = page_by_url(site, '/archive/news/slice/2/')

			expect(first_page).not_to be_nil
			expect(second_page).not_to be_nil
			expect(second_page.data.fetch('title')).to eq('Archive news / news / 2')
			expect(paginator_item_titles(second_page)).to eq(['Post 01'])
		end
	end
end
