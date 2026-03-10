# frozen_string_literal: true

RSpec.describe 'Pagination integration: core behaviour' do
	it 'paginates a template into generated index pages with paginator payloads' do
		files = jekyll_merge(
			post_files(5),
			jekyll_files do
				file 'index.md' do
					frontmatter(
						pagination_template_frontmatter(
							{
								'title' => 'Home',
								'pagination' => {
									'enabled' => true,
									'items' => 'posts',
									'per_page' => 2,
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
			generated_pages = generated_pagination_pages(site).sort_by { |page| paginator_index_number(page) }
			expect(generated_pages.map { |page| normalise_url_for_match(page.url) }).to eq(['/', '/page/2', '/page/3'])

			expect(paginator_item_titles(generated_pages[0])).to eq(['Post 01', 'Post 02'])
			expect(paginator_item_titles(generated_pages[1])).to eq(['Post 03', 'Post 04'])
			expect(paginator_item_titles(generated_pages[2])).to eq(['Post 05'])

			expect(paginator_reference_number(generated_pages[0], 'next')).to eq(2)
			expect(normalise_url_for_match(paginator_reference_url(generated_pages[0], 'next'))).to eq('/page/2')
			expect(paginator_reference_number(generated_pages[2], 'next')).to be_nil
			expect(generated_pages[0].data.dig('pagination', 'template')).to be_nil
			expect(generated_pages[0].data.dig('pagination', 'enabled')).to be_nil
			expect(generated_pages[0].data.dig('pagination', 'index')).to eq(true)
		end
	end

	it 'excludes hidden content and pagination templates from resolved items' do
		files = jekyll_merge(
			post_files(3) do |index|
				index == 2 ? { 'hidden' => true } : {}
			end,
			jekyll_files do
				file 'index.md' do
					frontmatter(
						pagination_template_frontmatter(
							{
								'title' => 'Template',
								'pagination' => {
									'enabled' => true,
									'items' => 'everything',
									'sort' => 'title asc',
									'per_page' => 50
								}
							}
						)
					)
					contents('Template content')
				end

				folder 'docs' do
					file 'visible.md' do
						frontmatter('layout' => 'listing', 'title' => 'Visible Page')
						contents('Visible')
					end

					file 'hidden.md' do
						frontmatter('layout' => 'listing', 'title' => 'Hidden Page', 'hidden' => true)
						contents('Hidden')
					end
				end
			end
		)

		jekyll_build(default_site, files: files) do |site,|
			first_page = page_by_url(site, '/')
			titles = paginator_item_titles(first_page)

			expect(titles).to include('Post 01', 'Post 03', 'Visible Page')
			expect(titles).not_to include('Post 02')
			expect(titles).not_to include('Hidden Page')
			expect(titles).not_to include('Template')
		end
	end

	it 'applies offset and limit after sorting to cap the item set' do
		files = jekyll_merge(
			post_files(8),
			jekyll_files do
				file 'index.md' do
					frontmatter(
						pagination_template_frontmatter(
							{
								'pagination' => {
									'enabled' => true,
									'items' => 'posts',
									'sort' => 'title asc',
									'per_page' => 2,
									'offset' => 3,
									'limit' => 2
								}
							}
						)
					)
					contents('Template content')
				end
			end
		)

		jekyll_build(default_site, files: files) do |site,|
			generated_pages = generated_pagination_pages(site).sort_by { |page| paginator_index_number(page) }
			expect(generated_pages.map { |page| normalise_url_for_match(page.url) }).to eq(['/'])

			expect(paginator_item_titles(generated_pages[0])).to eq(['Post 04', 'Post 05'])
			expect(generated_pages[1]).to be_nil
			expect(page_by_url(site, '/page/2/')).to be_nil
			expect(page_by_url(site, '/page/3/')).to be_nil
		end
	end

	it 'merges template pagination with layout pagination and keeps template precedence by default' do
		files = jekyll_merge(
			post_files(3),
			jekyll_files do
				folder '_layouts' do
					file 'paged.html' do
						frontmatter(
							'pagination' => {
								'sort' => 'title desc',
								'per_page' => 2
							}
						)
						contents('{{ content }}')
					end
				end

				file 'index.md' do
					frontmatter(
						pagination_template_frontmatter(
							{
								'layout' => 'paged',
								'pagination' => {
									'enabled' => true,
									'items' => 'posts',
									'per_page' => 1
								}
							}
						)
					)
					contents('Template content')
				end
			end
		)

		jekyll_build(default_site, files: files) do |site,|
			page_one = page_by_url(site, '/')
			page_two = page_by_url(site, '/page/2/')
			page_three = page_by_url(site, '/page/3/')

			expect(page_one).not_to be_nil
			expect(page_two).not_to be_nil
			expect(page_three).not_to be_nil
			expect(paginator_item_titles(page_one)).to eq(['Post 03'])
		end
	end

	it 'merges template pagination with layout pagination and gives layout precedence in v2 mode' do
		files = jekyll_merge(
			post_files(3),
			jekyll_files do
				folder '_layouts' do
					file 'paged.html' do
						frontmatter(
							'pagination' => {
								'sort' => 'title desc',
								'per_page' => 2
							}
						)
						contents('{{ content }}')
					end
				end

				file 'index.md' do
					frontmatter(
						pagination_template_frontmatter(
							{
								'layout' => 'paged',
								'pagination' => {
									'enabled' => true,
									'items' => 'posts',
									'per_page' => 1
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
					'enabled' => true,
					'compatibility' => 'v2'
				}
			},
			files: files
		) do |site,|
			page_one = page_by_url(site, '/')
			page_two = page_by_url(site, '/page/2/')
			page_three = page_by_url(site, '/page/3/')

			expect(page_one).not_to be_nil
			expect(page_two).not_to be_nil
			expect(page_three).to be_nil
			expect(paginator_item_titles(page_one)).to eq(['Post 03', 'Post 02'])
		end
	end

	it 'supports per_page as a variable page-size array' do
		files = jekyll_merge(
			post_files(10),
			jekyll_files do
				file 'index.md' do
					frontmatter(
						pagination_template_frontmatter(
							{
								'pagination' => {
									'enabled' => true,
									'items' => 'posts',
									'sort' => 'title asc',
									'per_page' => [3, 1, 2]
								}
							}
						)
					)
					contents('Template content')
				end
			end
		)

		jekyll_build(default_site, files: files) do |site,|
			page_one = page_by_url(site, '/')
			page_two = page_by_url(site, '/page/2/')
			page_three = page_by_url(site, '/page/3/')
			page_four = page_by_url(site, '/page/4/')
			page_five = page_by_url(site, '/page/5/')

			expect(page_one).not_to be_nil
			expect(page_two).not_to be_nil
			expect(page_three).not_to be_nil
			expect(page_four).not_to be_nil
			expect(page_five).not_to be_nil
			expect(page_by_url(site, '/page/6/')).to be_nil

			expect(paginator_item_titles(page_one)).to eq(['Post 01', 'Post 02', 'Post 03'])
			expect(paginator_item_titles(page_two)).to eq(['Post 04'])
			expect(paginator_item_titles(page_three)).to eq(['Post 05', 'Post 06'])
			expect(paginator_item_titles(page_four)).to eq(['Post 07', 'Post 08'])
			expect(paginator_item_titles(page_five)).to eq(['Post 09', 'Post 10'])

			page_four_payload = paginator_payload(page_four)
			expect(page_four_payload.fetch('current').count).to eq(2)
			expect(page_four_payload.fetch('current').start).to eq(7)
			expect(page_four_payload.fetch('current').to_h['end']).to eq(8)

			expect(paginator_reference_number(page_three, 'next')).to eq(4)
			expect(normalise_url_for_match(paginator_reference_url(page_three, 'next'))).to eq('/page/4')
			expect(paginator_reference_number(page_five, 'next')).to be_nil
		end
	end
end
