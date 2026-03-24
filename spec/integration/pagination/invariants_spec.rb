# frozen_string_literal: true

RSpec.describe 'Pagination integration: invariants and edge behaviour' do
	it 'excludes previously generated index pages from later item resolution' do
		files = jekyll_merge(
			post_files(2),
			jekyll_files do
				file 'a-template.md' do
					frontmatter(
						pagination_template_frontmatter(
							{
								'title' => 'Alpha Template',
								'permalink' => '/alpha/',
								'pagination' => {
									'enabled' => true,
									'items' => 'posts',
									'sort' => 'title asc',
									'per_page' => 1
								}
							}
						)
					)
					contents('Alpha template')
				end

				file 'z-template.md' do
					frontmatter(
						pagination_template_frontmatter(
							{
								'title' => 'Mixed Listing',
								'permalink' => '/mixed/',
								'pagination' => {
									'enabled' => true,
									'items' => 'everything',
									'sort' => 'title asc',
									'per_page' => 50
								}
							}
						)
					)
					contents('Mixed template')
				end

				folder 'docs' do
					file 'guide.md' do
						frontmatter('layout' => 'listing', 'title' => 'Guide Page')
						contents('Guide content')
					end
				end
			end
		)

		jekyll_build(default_site, files: files) do |site,|
			mixed_page = page_by_url(site, '/mixed/')
			titles = paginator_item_titles(mixed_page)

			expect(titles).to eq(['Guide Page', 'Post 01', 'Post 02'])
			expect(titles).not_to include('Alpha Template', 'Alpha Template - page 2')
		end
	end

	it 'still emits page one when filters remove all candidate items' do
		files = jekyll_merge(
			post_files(2) do |index|
				index == 1 ? { 'category' => 'news' } : { 'category' => 'updates' }
			end,
			jekyll_files do
				file 'index.md' do
					frontmatter(
						pagination_template_frontmatter(
							{
								'title' => 'Empty Listing',
								'pagination' => {
									'enabled' => true,
									'items' => 'posts',
									'sort' => 'title asc',
									'per_page' => 1,
									'filters' => {
										'category' => 'non-existent'
									}
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
			first_page_payload = paginator_payload(generated_pages.first)

			expect(generated_pages.map(&:url)).to eq(['/'])
			expect(first_page_payload.fetch('total_items')).to eq(0)
			expect(first_page_payload.fetch('total_indexes')).to eq(1)
			expect(first_page_payload.fetch('items')).to eq([])
			expect(paginator_reference_number(generated_pages.first, 'next')).to be_nil
		end
	end

	it 'skips pagination processing entirely when globally disabled' do
		files = jekyll_merge(
			post_files(3),
			jekyll_files do
				file 'index.md' do
					frontmatter(
						pagination_template_frontmatter(
							{
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
					'enabled' => false
				}
			},
			files: files
		) do |site,|
			root_page = page_by_url(site, '/')

			expect(root_page).not_to be_nil
			expect(root_page.data['paginator']).to be_nil
			expect(generated_pagination_pages(site)).to eq([])
			expect(page_by_url(site, '/page/2/')).to be_nil
		end
	end

	it 'builds successfully when pagination is enabled but no templates are discovered' do
		files = jekyll_merge(
			post_files(2),
			jekyll_files do
				file 'index.md' do
					frontmatter('layout' => 'listing', 'title' => 'Home')
					contents('Home content')
				end
			end
		)

		jekyll_build(default_site, files: files) do |site,|
			root_page = page_by_url(site, '/')

			expect(root_page).not_to be_nil
			expect(root_page.data['paginator']).to be_nil
			expect(generated_pagination_pages(site)).to eq([])
		end
	end
end
