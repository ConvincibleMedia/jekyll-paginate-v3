# frozen_string_literal: true

RSpec.describe 'Pagination integration: v1' do
	it 'automatically enables v1 mode when legacy paginate config is present' do
		files = jekyll_merge(
			post_files(3),
			jekyll_files do
				file 'index.html' do
					frontmatter('layout' => 'listing', 'title' => 'Legacy Home')
					contents('Legacy home')
				end
			end
		)

		jekyll_build(
			default_site,
			config: {
				'paginate' => 2,
				'paginate_path' => '/legacy/page:num/'
			},
			files: files
		) do |site,|
			first_page = page_by_url(site, '/')
			second_page = page_by_url(site, '/legacy/page2/')

			expect(first_page).not_to be_nil
			expect(second_page).not_to be_nil
			expect(paginator_item_titles(first_page)).to eq(['Post 03', 'Post 02'])
			expect(paginator_payload(first_page)).to include('posts', 'total_posts')
		end
	end

	it 'uses explicit pagination templates in v1 mode when present' do
		files = jekyll_merge(
			post_files(2),
			jekyll_files do
				file 'index.html' do
					frontmatter('layout' => 'listing', 'title' => 'Root Page')
					contents('Root')
				end

				folder 'blog' do
					file 'index.md' do
						frontmatter(
							pagination_template_frontmatter(
								{
									'title' => 'Blog',
									'permalink' => '/blog/',
									'pagination' => {
										'enabled' => true,
										'items' => 'posts',
										'per_page' => 1,
										'sort' => 'title asc'
									}
								}
							)
						)
						contents('Template content')
					end
				end
			end
		)

		jekyll_build(
			default_site,
			config: {
				'pagination' => {
					'enabled' => true,
					'compatibility' => 'v1'
				}
			},
			files: files
		) do |site,|
			blog_page_one = page_by_url(site, '/blog/')
			root_page = page_by_url(site, '/')
			next_reference = paginator_payload(blog_page_one).fetch('next')
			blog_page_two = next_reference.respond_to?(:page) ? next_reference.page : next_reference['page']

			expect(blog_page_one).not_to be_nil
			expect(blog_page_two).not_to be_nil
			expect(root_page.data['paginator']).to be_nil
			expect(paginator_item_titles(blog_page_one)).to eq(['Post 01'])
			expect(paginator_item_titles(blog_page_two)).to eq(['Post 02'])
		end
	end

	it 'chooses the deepest legacy index candidate in paginate path hierarchy' do
		files = jekyll_merge(
			post_files(2),
			jekyll_files do
				file 'index.html' do
					frontmatter('layout' => 'listing', 'title' => 'Root Index')
					contents('Root index')
				end

				folder 'news' do
					file 'index.html' do
						frontmatter('layout' => 'listing', 'title' => 'News Index')
						contents('News index')
					end

					folder 'archive' do
						file 'index.html' do
							frontmatter('layout' => 'listing', 'title' => 'Archive Index')
							contents('Archive index')
						end
					end
				end
			end
		)

		jekyll_build(
			default_site,
			config: {
				'paginate' => 1,
				'paginate_path' => '/news/archive/page:num/'
			},
			files: files
		) do |site,|
			archive_first_page = page_by_url(site, '/news/archive/')
			archive_second_page = page_by_url(site, '/news/archive/page2/')
			root_page = page_by_url(site, '/')

			expect(archive_first_page).not_to be_nil
			expect(archive_second_page).not_to be_nil
			expect(root_page.data['paginator']).to be_nil
			expect(paginator_item_titles(archive_first_page)).to eq(['Post 02'])
			expect(paginator_item_titles(archive_second_page)).to eq(['Post 01'])
		end
	end

	it 'supports a complex legacy v1 setup with only legacy keys plus compatibility mode' do
		files = jekyll_merge(
			post_files(7) do |index|
				index == 6 ? { 'hidden' => true } : {}
			end,
			jekyll_files do
				file 'index.html' do
					frontmatter('layout' => 'listing', 'title' => 'Site Root')
					contents('Root')
				end

				folder 'blog' do
					file 'index.html' do
						frontmatter('layout' => 'listing', 'title' => 'Blog Root')
						contents('Blog root')
					end

					folder 'archive' do
						file 'index.html' do
							frontmatter('layout' => 'listing', 'title' => 'Archive Root')
							contents('Archive root')
						end
					end
				end
			end
		)

		jekyll_build(
			default_site,
			config: {
				'paginate' => 2,
				'paginate_path' => '/blog/archive/page:num/',
				'pagination' => {
					'compatibility' => 'v1'
				}
			},
			files: files
		) do |site,|
			archive_page_one = page_by_url(site, '/blog/archive/')
			archive_page_two = page_by_url(site, '/blog/archive/page2/')
			archive_page_three = page_by_url(site, '/blog/archive/page3/')
			root_page = page_by_url(site, '/')

			expect(archive_page_one).not_to be_nil
			expect(archive_page_two).not_to be_nil
			expect(archive_page_three).not_to be_nil
			expect(root_page.data['paginator']).to be_nil

			expect(paginator_item_titles(archive_page_one)).to eq(['Post 07', 'Post 05'])
			expect(paginator_item_titles(archive_page_two)).to eq(['Post 04', 'Post 03'])
			expect(paginator_item_titles(archive_page_three)).to eq(['Post 02', 'Post 01'])

			page_one_payload = paginator_payload(archive_page_one)
			page_two_payload = paginator_payload(archive_page_two)
			page_three_payload = paginator_payload(archive_page_three)

			expect(page_one_payload).to include('posts', 'total_posts')
			expect(page_one_payload.fetch('total_posts')).to eq(6)
			expect(page_one_payload.fetch('next_page_path')).to eq('/blog/archive/page2/')
			expect(page_two_payload.fetch('previous_page_path')).to eq('/blog/archive/')
			expect(page_three_payload.fetch('next_page')).to be_nil
		end
	end
end
