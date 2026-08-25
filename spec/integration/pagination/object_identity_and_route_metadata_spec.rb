# frozen_string_literal: true

unless defined?(PaginateV3IdentityProbeGenerator)
	# Captures pagination templates before the lowest-priority PV3 generator runs
	# so integration examples can verify exact identity and plugin-owned state.
	class PaginateV3IdentityProbeGenerator < Jekyll::Generator

		safe true
		priority :high

		def generate(site)
			return unless site.config['pagination_identity_probe']

			template = (site.pages + site.collections.values.flat_map(&:docs)).find do |item|
				item.data['pagination_identity_probe']
			end
			return if template.nil?

			plugin_state = Object.new
			relationship = { 'page' => template }
			template.instance_variable_set(:@pagination_identity_probe_state, plugin_state)
			template.data['relationship_reference'] = relationship
			site.config['pagination_identity_probe_result'] = {
				'template' => template,
				'plugin_state' => plugin_state,
				'relationship' => relationship,
				'collection_index' => template.is_a?(Jekyll::Document) ? template.collection.docs.index(template) : site.pages.index(template)
			}
		end
	end
end

RSpec.describe 'Pagination integration: object identity and route metadata' do
	it 'isolates mutable frontmatter containers between a template and its generated pages' do
		files = jekyll_merge(
			post_files(3),
			jekyll_files do
				file 'index.md' do
					frontmatter(
						pagination_template_frontmatter(
							{
								'meta' => { 'id' => 'source' },
								'seo' => { 'description' => 'Source description' },
								'tags' => ['source'],
								'content_configuration' => [{ 'enabled' => true }],
								'pagination' => {
									'enabled' => true,
									'items' => 'posts',
									'per_page' => 1,
									'permalink' => 'page/{{ num }}'
								}
							}
						)
					)
					contents('Home')
				end
			end
		)

		jekyll_build(default_site, files: files) do |site,|
			template = page_by_url(site, '/')
			page_two = page_by_url(site, '/page/2/')
			page_three = page_by_url(site, '/page/3/')

			page_two.data.fetch('meta')['id'] = 'page-two'
			page_two.data.fetch('seo')['description'] = 'Page two description'
			page_two.data.fetch('pagination')['custom'] = true
			page_two.data.fetch('tags') << 'page-two'
			page_two.data.fetch('content_configuration').first['enabled'] = false

			[template, page_three].each do |other_page|
				expect(other_page.data.dig('meta', 'id')).to eq('source')
				expect(other_page.data.dig('seo', 'description')).to eq('Source description')
				expect(other_page.data.fetch('pagination')).not_to have_key('custom')
				expect(other_page.data.fetch('tags')).not_to include('page-two')
				expect(other_page.data.fetch('content_configuration').first['enabled']).to be(true)

				expect(page_two.data).not_to equal(other_page.data)
				expect(page_two.data.fetch('meta')).not_to equal(other_page.data.fetch('meta'))
				expect(page_two.data.fetch('pagination')).not_to equal(other_page.data.fetch('pagination'))
				expect(page_two.data.fetch('tags')).not_to equal(other_page.data.fetch('tags'))
				expect(page_two.data.fetch('content_configuration')).not_to equal(other_page.data.fetch('content_configuration'))
				expect(page_two.data.fetch('content_configuration').first).not_to equal(other_page.data.fetch('content_configuration').first)
			end
		end
	end

	it 'retains a single page variant and exposes its base and resolved paths' do
		files = jekyll_merge(
			post_files(2),
			jekyll_files do
				folder 'articles' do
					file 'index.md' do
						frontmatter(
							pagination_template_frontmatter(
								{
									'pagination_identity_probe' => true,
									'consumer' => {
										'id' => 34_234,
										'labels' => %w[primary listing]
									},
									'pagination' => {
										'enabled' => true,
										'items' => 'posts',
										'per_page' => 1,
										'permalink' => 'page/{{ num }}'
									}
								}
							)
						)
						contents('Articles')
					end
				end
			end
		)

		jekyll_build(default_site, config: { 'pagination_identity_probe' => true }, files: files) do |site,|
			probe = site.config.fetch('pagination_identity_probe_result')
			page_one = page_by_url(site, '/articles/')
			page_two = page_by_url(site, '/articles/page/2/')

			expect(page_one).to equal(probe.fetch('template'))
			expect(probe.dig('relationship', 'page')).to equal(page_one)
			expect(page_one.instance_variable_get(:@pagination_identity_probe_state)).to equal(probe.fetch('plugin_state'))
			expect(site.pages.fetch(probe.fetch('collection_index'))).to equal(page_one)
			expect(page_one.data.fetch('consumer')).to eq('id' => 34_234, 'labels' => %w[primary listing])
			expect(page_two.data.fetch('consumer')).to eq('id' => 34_234, 'labels' => %w[primary listing])
			expect(page_one.data.fetch('pagination')).to include('base' => '/articles', 'path' => '')
			expect(page_two.data.fetch('pagination')).to include('base' => '/articles', 'path' => 'page/2')
		end
	end

	[
		{ 'items' => 0, 'indexes' => 1, 'collection' => nil },
		{ 'items' => 1, 'indexes' => 1, 'collection' => nil },
		{ 'items' => 2, 'indexes' => 2, 'collection' => 'self' }
	].each do |scenario|
		it "retains a self-targeted document with #{scenario['items']} item(s)" do
			pagination_config = {
				'enabled' => true,
				'items' => 'posts',
				'per_page' => 1
			}
			pagination_config['collection'] = scenario['collection'] unless scenario['collection'].nil?
			files = [
				post_files(scenario['items']),
				collection_document('products', 'before.md', { 'title' => 'Before' }, 'Before'),
				collection_document(
					'products',
					'widgets.md',
					pagination_template_frontmatter(
						{
							'pagination_identity_probe' => true,
							'permalink' => '/products/widgets/',
							'pagination' => pagination_config
						}
					),
					'Widgets'
				),
				collection_document('products', 'after.md', { 'title' => 'After' }, 'After')
			].reduce { |combined, entry| jekyll_merge(combined, entry) }

			jekyll_build(
				default_site,
				config: {
					'pagination_identity_probe' => true,
					'pagination' => {
						'enabled' => true,
						'templates' => {
							'location' => 'products'
						}
					}
				},
				files: files
			) do |site,|
				probe = site.config.fetch('pagination_identity_probe_result')
				indexes = generated_pagination_documents(site, 'products').sort_by { |item| paginator_index_number(item) }

				expect(indexes.length).to eq(scenario['indexes'])
				expect(indexes.first).to equal(probe.fetch('template'))
				expect(probe.dig('relationship', 'page')).to equal(indexes.first)
				expect(indexes.first.instance_variable_get(:@pagination_identity_probe_state)).to equal(probe.fetch('plugin_state'))
				expect(site.collections.fetch('products').docs.fetch(probe.fetch('collection_index'))).to equal(indexes.first)
				if scenario['indexes'] > 1
					expect(site.collections.fetch('products').docs.fetch(probe.fetch('collection_index') + 1)).to equal(indexes[1])
				end
			end
		end
	end

	it 'retains one grouped variant while exposing its group and page fragments' do
		files = jekyll_merge(
			post_files(2) { { 'category' => 'fertiliser' } },
			jekyll_files do
				folder '34234' do
					file 'index.md' do
						frontmatter(
							pagination_template_frontmatter(
								{
									'pagination_identity_probe' => true,
									'pagination' => {
										'enabled' => true,
										'items' => 'posts',
										'group' => 'category',
										'per_page' => 1,
										'permalink' => 'category/{{ category }} page/{{ num }}'
									}
								}
							)
						)
						contents('Products')
					end
				end
			end
		)

		jekyll_build(default_site, config: { 'pagination_identity_probe' => true }, files: files) do |site,|
			probe = site.config.fetch('pagination_identity_probe_result')
			page_one = page_by_url(site, '/34234/category/fertiliser/')
			page_two = page_by_url(site, '/34234/category/fertiliser/page/2/')

			expect(page_one).to equal(probe.fetch('template'))
			expect(page_by_url(site, '/34234/')).to be_nil
			expect(page_one.data.fetch('pagination')).to include('base' => '/34234', 'path' => 'category/fertiliser')
			expect(page_two.data.fetch('pagination')).to include('base' => '/34234', 'path' => 'category/fertiliser/page/2')
		end
	end

	it 'generates independent page-one objects when expansion produces multiple variants' do
		files = jekyll_merge(
			post_files(2) { |number| { 'category' => number == 1 ? 'news' : 'guides' } },
			jekyll_files do
				folder 'articles' do
					file 'index.md' do
						frontmatter(
							pagination_template_frontmatter(
								{
									'pagination_identity_probe' => true,
									'pagination' => {
										'enabled' => true,
										'items' => 'posts',
										'group' => 'category',
										'permalink' => 'category/{{ category }} page/{{ num }}'
									}
								}
							)
						)
						contents('Articles')
					end
				end
			end
		)

		jekyll_build(default_site, config: { 'pagination_identity_probe' => true }, files: files) do |site,|
			probe = site.config.fetch('pagination_identity_probe_result')
			news_page = page_by_url(site, '/articles/category/news/')
			guides_page = page_by_url(site, '/articles/category/guides/')

			expect(news_page).not_to equal(probe.fetch('template'))
			expect(guides_page).not_to equal(probe.fetch('template'))
			expect(site.pages).not_to include(probe.fetch('template'))
			expect(news_page.data.fetch('pagination')).to include('base' => '/articles', 'path' => 'category/news')
			expect(guides_page.data.fetch('pagination')).to include('base' => '/articles', 'path' => 'category/guides')
		end
	end

	it 'creates a page when a document template targets pages' do
		files = jekyll_merge(
			post_files(1),
			collection_document(
				'products',
				'widgets.md',
				pagination_template_frontmatter(
					{
						'pagination_identity_probe' => true,
						'permalink' => '/products/widgets/',
						'pagination' => {
							'enabled' => true,
							'items' => 'posts',
							'collection' => 'pages'
						}
					}
				),
				'Widgets'
			)
		)

		jekyll_build(
			default_site,
			config: {
				'pagination_identity_probe' => true,
				'pagination' => {
					'enabled' => true,
					'templates' => {
						'location' => 'products'
					}
				}
			},
			files: files
		) do |site,|
			probe = site.config.fetch('pagination_identity_probe_result')
			page_one = page_by_url(site, '/products/widgets/')

			expect(page_one).to be_a(Jekyll::Page)
			expect(page_one).not_to equal(probe.fetch('template'))
			expect(site.collections.fetch('products').docs).not_to include(probe.fetch('template'))
		end
	end
end
