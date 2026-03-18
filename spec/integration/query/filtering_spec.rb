# frozen_string_literal: true

RSpec.describe 'Pagination integration: filter semantics' do
	it 'supports scalar and delimited string shortcuts for include matching' do
		files = post_files(4) do |index|
			case index
			when 1 then { 'category' => 'news' }
			when 2 then { 'category' => 'blog' }
			when 3 then { 'category' => 'updates' }
			else { 'category' => 'other' }
			end
		end
		files = jekyll_merge(
			files,
			jekyll_files do
				file 'index.md' do
					frontmatter(
						pagination_template_frontmatter(
							{
								'pagination' => {
									'enabled' => true,
									'items' => 'posts',
									'sort' => 'title asc',
									'per_page' => 50,
									'filters' => {
										'category' => 'news,updates'
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
			expect(paginator_item_titles(page_by_url(site, '/'))).to eq(['Post 01', 'Post 03'])
		end
	end

	it 'supports scalar hash modes including only and first(N)' do
		files = post_files(3) do |index|
			case index
			when 1 then { 'tags' => ['ruby'], 'contributors' => ['alice', 'bob'] }
			when 2 then { 'tags' => ['ruby', 'jekyll'], 'contributors' => ['bob', 'alice'] }
			else { 'tags' => ['ruby'], 'contributors' => ['carol', 'dana'] }
			end
		end
		files = jekyll_merge(
			files,
			jekyll_files do
				file 'index.md' do
					frontmatter(
						pagination_template_frontmatter(
							{
								'pagination' => {
									'enabled' => true,
									'items' => 'posts',
									'sort' => 'title asc',
									'per_page' => 50,
									'filters' => {
										'tags' => {
											'match' => 'ruby',
											'mode' => 'only'
										},
										'contributors' => {
											'match' => 'alice',
											'mode' => 'first(2)',
											'split' => false
										}
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
			expect(paginator_item_titles(page_by_url(site, '/'))).to eq(['Post 01'])
		end
	end

	it 'treats nested multi-value matches as array values for strict filters' do
		files = post_files(3) do |index|
			case index
			when 1 then { 'authors' => [{ 'name' => 'ruby' }, { 'name' => 'jekyll' }] }
			when 2 then { 'authors' => [{ 'name' => 'ruby' }] }
			else { 'authors' => [{ 'name' => 'jekyll' }] }
			end
		end
		files = jekyll_merge(
			files,
			jekyll_files do
				file 'index.md' do
					frontmatter(
						pagination_template_frontmatter(
							{
								'pagination' => {
									'enabled' => true,
									'items' => 'posts',
									'sort' => 'title asc',
									'per_page' => 50,
									'filters' => {
										'authors.name' => {
											'match' => 'ruby',
											'mode' => 'strict',
											'split' => false
										}
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
			expect(paginator_item_titles(page_by_url(site, '/'))).to eq(['Post 02'])
		end
	end

	it 'supports numeric range filters and swaps inverted bounds' do
		files = jekyll_merge(
			post_files(5) { |index| { 'rating' => index } },
			jekyll_files do
				file 'index.md' do
					frontmatter(
						pagination_template_frontmatter(
							{
								'pagination' => {
									'enabled' => true,
									'items' => 'posts',
									'sort' => 'title asc',
									'per_page' => 50,
									'filters' => {
										'rating' => {
											'min' => 4,
											'max' => 2
										}
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
			expect(paginator_item_titles(page_by_url(site, '/'))).to eq(['Post 02', 'Post 03', 'Post 04'])
		end
	end

	it 'supports range filters with configurable now keyword expressions' do
		current_time = DateTime.now

		files = post_files(3) do |index|
			published_at = case index
										 when 1 then (current_time - Rational(7_200, 86_400)).iso8601
										 when 2 then current_time.iso8601
										 else (current_time + Rational(7_200, 86_400)).iso8601
										 end

			{ 'published_at' => published_at }
		end
		files = jekyll_merge(
			files,
			jekyll_files do
				file 'index.md' do
					frontmatter(
						pagination_template_frontmatter(
							{
								'pagination' => {
									'enabled' => true,
									'items' => 'posts',
									'sort' => 'title asc',
									'per_page' => 50,
									'filters' => {
										'published_at' => {
											'min' => 'secondnow - 3600',
											'max' => 'secondnow + 3600'
										}
									}
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
					'keywords' => {
						'now' => 'secondnow'
					}
				}
			},
			files: files
		) do |site,|
			expect(paginator_item_titles(page_by_url(site, '/'))).to eq(['Post 02'])
		end
	end

	it 'supports inclusive/exclusive range mode controls' do
		files = jekyll_merge(
			post_files(4) do |index|
				{ 'rating' => index }
			end,
			jekyll_files do
				file 'index.md' do
					frontmatter(
						pagination_template_frontmatter(
							{
								'pagination' => {
									'enabled' => true,
									'items' => 'posts',
									'sort' => 'title asc',
									'per_page' => 50,
									'filters' => {
										'rating' => {
											'min' => 2,
											'max' => 4,
											'mode' => 'min-exclusive max-inclusive'
										}
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
			expect(paginator_item_titles(page_by_url(site, '/'))).to eq(['Post 03', 'Post 04'])
		end
	end

	it 'supports today keyword day ranges with implicit min and max times' do
		current_time = DateTime.now
		start_of_today = DateTime.new(current_time.year, current_time.month, current_time.day, 0, 0, 0, current_time.offset)

		files = post_files(4) do |index|
			published_at = case index
										 when 1 then (start_of_today - 2 + Rational(43_200, 86_400)).iso8601
										 when 2 then (start_of_today - 1 + Rational(43_200, 86_400)).iso8601
										 when 3 then (start_of_today + Rational(86_399, 86_400)).iso8601
										 else (start_of_today + 1 + Rational(43_200, 86_400)).iso8601
										 end

			{ 'published_at' => published_at }
		end
		files = jekyll_merge(
			files,
			jekyll_files do
				file 'index.md' do
					frontmatter(
						pagination_template_frontmatter(
							{
								'pagination' => {
									'enabled' => true,
									'items' => 'posts',
									'sort' => 'title asc',
									'per_page' => 50,
									'filters' => {
										'published_at' => {
											'min' => 'daykeyword - 1',
											'max' => 'daykeyword'
										}
									}
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
					'keywords' => {
						'today' => 'daykeyword'
					}
				}
			},
			files: files
		) do |site,|
			expect(paginator_item_titles(page_by_url(site, '/'))).to eq(['Post 02', 'Post 03'])
		end
	end

	it 'supports nested key lookup, equivalent keys, and include/exclude groups' do
		files = post_files(4) do |index|
			case index
			when 1 then { 'author' => { 'name' => 'Alice' }, 'topics' => ['ruby', 'jekyll'], 'status' => 'published' }
			when 2 then { 'author' => { 'name' => 'Alice' }, 'tag' => 'ruby', 'status' => 'archived' }
			when 3 then { 'author' => { 'name' => 'Adam' }, 'topics' => ['ruby'], 'status' => 'draft' }
			else { 'author' => { 'name' => 'Bob' }, 'topics' => ['ruby'], 'status' => 'published' }
			end
		end
		files = jekyll_merge(
			files,
			jekyll_files do
				file 'index.md' do
					frontmatter(
						pagination_template_frontmatter(
							{
								'pagination' => {
									'enabled' => true,
									'items' => 'posts',
									'sort' => 'title asc',
									'per_page' => 50,
									'filters' => {
										'author.name' => '/^A/',
										'tag' => 'ruby',
										'status' => {
											'include' => 'published,draft',
											'exclude' => 'archived',
											'join' => 'or'
										}
									}
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
					'equivalents' => [
						%w[tag topics]
					]
				}
			},
			files: files
		) do |site,|
			expect(paginator_item_titles(page_by_url(site, '/'))).to eq(['Post 01', 'Post 03'])
		end
	end

	it 'supports nested include and exclude groups using join-and semantics' do
		files = post_files(5) do |index|
			labels = case index
							 when 1 then %w[ruby jekyll]
							 when 2 then ['ruby']
							 when 3 then %w[jekyll featured]
							 when 4 then %w[ruby jekyll internal private]
							 else ['featured']
							 end

			{ 'labels' => labels }
		end
		files = jekyll_merge(
			files,
			jekyll_files do
				file 'index.md' do
					frontmatter(
						pagination_template_frontmatter(
							{
								'pagination' => {
									'enabled' => true,
									'items' => 'posts',
									'sort' => 'title asc',
									'per_page' => 50,
									'filters' => {
										'labels' => {
											'include' => [
												{
													'include' => %w[ruby jekyll],
													'join' => 'and'
												},
												'featured'
											],
											'exclude' => {
												'include' => %w[internal private],
												'join' => 'and'
											},
											'join' => 'or'
										}
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
			expect(paginator_item_titles(page_by_url(site, '/'))).to eq(['Post 01', 'Post 03', 'Post 05'])
		end
	end

	it 'scopes equivalent keys to full nested key paths' do
		files = post_files(3) do |index|
			case index
			when 1 then { 'product' => { 'tags' => ['ruby'] } }
			when 2 then { 'product' => { 'tag' => 'ruby' } }
			else { 'tags' => ['ruby'] }
			end
		end
		files = jekyll_merge(
			files,
			jekyll_files do
				file 'index.md' do
					frontmatter(
						pagination_template_frontmatter(
							{
								'pagination' => {
									'enabled' => true,
									'items' => 'posts',
									'sort' => 'title asc',
									'per_page' => 50,
									'filters' => {
										'product.tag' => 'ruby'
									}
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
					'equivalents' => [
						%w[tag tags]
					]
				}
			},
			files: files
		) do |site,|
			expect(paginator_item_titles(page_by_url(site, '/'))).to eq(['Post 02'])
		end

		jekyll_build(
			default_site,
			config: {
				'pagination' => {
					'enabled' => true,
					'equivalents' => [
						%w[tag tags],
						['product.tag', 'product.tags']
					]
				}
			},
			files: files
		) do |site,|
			expect(paginator_item_titles(page_by_url(site, '/'))).to eq(['Post 01', 'Post 02'])
		end
	end

	it 'supports an alternate nested key separator for filters' do
		files = post_files(2) do |index|
			index == 1 ? { 'author' => { 'name' => 'Alice' } } : { 'author' => { 'name' => 'Bob' } }
		end

		jekyll_build(
			default_site,
			config: {
				'pagination' => {
					'enabled' => true,
					'syntax' => {
						'separator' => ':'
					}
				}
			},
			files: jekyll_merge(
				files,
				jekyll_files do
					file 'index.md' do
						frontmatter(
							pagination_template_frontmatter(
								{
									'pagination' => {
										'enabled' => true,
										'items' => 'posts',
										'sort' => 'title asc',
										'per_page' => 50,
										'filters' => {
											'author:name' => 'Alice'
										}
									}
								}
							)
						)
						contents('Template content')
					end
				end
			)
		) do |site,|
			expect(paginator_item_titles(page_by_url(site, '/'))).to eq(['Post 01'])
		end
	end

	it 'treats exists true and false as strict negations after value processing' do
		files = post_files(6) do |index|
			case index
			when 1 then {}
			when 2 then { 'meta' => { 'links' => { 'projects' => [] } } }
			when 3 then { 'meta' => { 'links' => { 'projects' => '' } } }
			when 4 then { 'meta' => { 'links' => { 'projects' => '   ' } } }
			when 5 then { 'meta' => { 'links' => { 'projects' => 'solo' } } }
			else { 'meta' => { 'links' => { 'projects' => 'one,two' } } }
			end
		end

		present_files = jekyll_merge(
			files,
			jekyll_files do
				file 'present.md' do
					frontmatter(
						pagination_template_frontmatter(
							{
								'permalink' => '/present/',
								'pagination' => {
									'enabled' => true,
									'items' => 'posts',
									'sort' => 'title asc',
									'per_page' => 50,
									'filters' => {
										'meta.links.projects' => {
											'exists' => true
										}
									}
								}
							}
						)
					)
					contents('Template content')
				end

				file 'missing.md' do
					frontmatter(
						pagination_template_frontmatter(
							{
								'permalink' => '/missing/',
								'pagination' => {
									'enabled' => true,
									'items' => 'posts',
									'sort' => 'title asc',
									'per_page' => 50,
									'filters' => {
										'meta.links.projects' => {
											'exists' => false
										}
									}
								}
							}
						)
					)
					contents('Template content')
				end
			end
		)

		jekyll_build(default_site, files: present_files) do |site,|
			expect(paginator_item_titles(page_by_url(site, '/present/'))).to eq(['Post 05', 'Post 06'])
			expect(paginator_item_titles(page_by_url(site, '/missing/'))).to eq(['Post 01', 'Post 02', 'Post 03', 'Post 04'])
		end
	end

	it 'supports exists type checks and length-aware ranges' do
		files = post_files(4) do |index|
			case index
			when 1 then { 'meta' => { 'links' => { 'projects' => 'one,two,three' } }, 'label' => 'Alpha', 'flag' => 'false', 'published_at' => '2026-01-01' }
			when 2 then { 'meta' => { 'links' => { 'projects' => 'one' } }, 'label' => 'Go', 'flag' => 'maybe', 'published_at' => 'not-a-date' }
			when 3 then { 'meta' => { 'links' => { 'projects' => [] } }, 'label' => 'Bravo', 'flag' => true, 'published_at' => Date.new(2026, 1, 2) }
			else { 'meta' => { 'links' => { 'projects' => 'solo' } }, 'label' => 'Echo', 'flag' => 'TRUE', 'published_at' => nil }
			end
		end

		files = jekyll_merge(
			files,
			jekyll_files do
				file 'array.md' do
					frontmatter(
						pagination_template_frontmatter(
							{
								'permalink' => '/array/',
								'pagination' => {
									'enabled' => true,
									'items' => 'posts',
									'sort' => 'title asc',
									'per_page' => 50,
									'filters' => {
										'meta.links.projects' => {
											'exists' => 'array',
											'min' => 2
										}
									}
								}
							}
						)
					)
					contents('Template content')
				end

				file 'string.md' do
					frontmatter(
						pagination_template_frontmatter(
							{
								'permalink' => '/string/',
								'pagination' => {
									'enabled' => true,
									'items' => 'posts',
									'sort' => 'title asc',
									'per_page' => 50,
									'filters' => {
										'label' => {
											'exists' => 'string',
											'min' => 4,
											'split' => false
										}
									}
								}
							}
						)
					)
					contents('Template content')
				end

				file 'boolean.md' do
					frontmatter(
						pagination_template_frontmatter(
							{
								'permalink' => '/boolean/',
								'pagination' => {
									'enabled' => true,
									'items' => 'posts',
									'sort' => 'title asc',
									'per_page' => 50,
									'filters' => {
										'flag' => {
											'exists' => 'boolean',
											'split' => false
										}
									}
								}
							}
						)
					)
					contents('Template content')
				end

				file 'date.md' do
					frontmatter(
						pagination_template_frontmatter(
							{
								'permalink' => '/date/',
								'pagination' => {
									'enabled' => true,
									'items' => 'posts',
									'sort' => 'title asc',
									'per_page' => 50,
									'filters' => {
										'published_at' => {
											'exists' => 'datetime',
											'split' => false
										}
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
			expect(paginator_item_titles(page_by_url(site, '/array/'))).to eq(['Post 01'])
			expect(paginator_item_titles(page_by_url(site, '/string/'))).to eq(['Post 01', 'Post 03', 'Post 04'])
			expect(paginator_item_titles(page_by_url(site, '/boolean/'))).to eq(['Post 01', 'Post 03', 'Post 04'])
			expect(paginator_item_titles(page_by_url(site, '/date/'))).to eq(['Post 01', 'Post 03'])
		end
	end

	it 'supports shared mode tokens across match and range behaviour in one hash' do
		files = post_files(3) do |index|
			case index
			when 1 then { 'audience' => 'news,alerts' }
			when 2 then { 'audience' => 'alerts' }
			else { 'audience' => 'news,updates' }
			end
		end
		files = jekyll_merge(
			files,
			jekyll_files do
				file 'index.md' do
					frontmatter(
						pagination_template_frontmatter(
							{
								'pagination' => {
									'enabled' => true,
									'items' => 'posts',
									'sort' => 'title asc',
									'per_page' => 50,
									'filters' => {
										'audience' => {
											'exists' => 'array',
											'match' => 'alerts',
											'min' => 1,
											'mode' => 'auto min-exclusive'
										}
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
			expect(paginator_item_titles(page_by_url(site, '/'))).to eq(['Post 01'])
		end
	end
end
