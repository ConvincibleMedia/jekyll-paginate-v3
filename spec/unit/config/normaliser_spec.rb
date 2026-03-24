# frozen_string_literal: true

RSpec.describe Jekyll::Plugins::PaginateV3::Config::Normaliser do
	describe '.normalise_site_config' do
		it 'coerces boundary values and falls back to safe defaults' do
			config = described_class.normalise_site_config(
				'pagination' => {
					'enabled' => 'yes',
					'syntax' => {
						'split' => nil,
						'separator' => ''
					},
					'templates' => {
						'location' => '',
						'generate' => {
							'items' => 'posts'
						},
						'per_page' => 0,
						'offset' => -5,
						'limit' => -3
					}
				}
			)

			expect(config['enabled']).to eq(true)
			expect(config['per_page']).to eq(1)
			expect(config['offset']).to eq(0)
			expect(config['limit']).to eq(0)
			expect(config.dig('syntax', 'split')).to eq(',')
			expect(config.dig('syntax', 'separator')).to eq('.')
			expect(config.dig('keywords', 'now')).to eq('now')
			expect(config.dig('keywords', 'today')).to eq('today')
			expect(config.dig('templates', 'location')).to eq('pages')
			expect(config['collection']).to eq(%w[self shadow])
			expect(config.dig('templates', 'generate')).to be_an(Array)
			expect(config.dig('templates', 'generate').length).to eq(1)
		end

		it 'supports disabling global split parsing with syntax.split false' do
			config = described_class.normalise_site_config(
				'pagination' => {
					'enabled' => true,
					'syntax' => {
						'split' => false
					}
				}
			)

			expect(config.dig('syntax', 'split')).to eq(false)
		end

		it 'uses sort_field and sort_reverse when sort is omitted' do
			config = described_class.normalise_site_config(
				'pagination' => {
					'enabled' => true,
					'sort' => nil,
					'sort_field' => 'title',
					'sort_reverse' => true
				}
			)

			expect(config['sort']).to eq(['title desc'])
		end

		it 'supports variable per-page definitions as arrays' do
			config = described_class.normalise_site_config(
				'pagination' => {
					'enabled' => true,
					'per_page' => [3, 1, 0, -4]
				}
			)

			expect(config['per_page']).to eq([3, 1, 1, 1])
		end

		it 'supports variable per-page definitions as delimited strings' do
			config = described_class.normalise_site_config(
				'pagination' => {
					'enabled' => true,
					'syntax' => {
						'split' => '|'
					},
					'per_page' => '4|2|1'
				}
			)

			expect(config['per_page']).to eq([4, 2, 1])
		end

		it 'normalises delimited equivalent groups with a custom split delimiter' do
			config = described_class.normalise_site_config(
				'pagination' => {
					'enabled' => true,
					'syntax' => {
						'split' => '|'
					},
					'equivalents' => 'tag|tags'
				}
			)

			expect(config['equivalents']).to eq([%w[tag tags]])
		end

		it 'supports nested_key_separator as a legacy alias for syntax.separator' do
			config = described_class.normalise_site_config(
				'pagination' => {
					'enabled' => true,
					'nested_key_separator' => ':',
					'sort_field' => 'author:name'
				}
			)

			expect(config.dig('syntax', 'separator')).to eq(':')
			expect(config['sort']).to eq(['author:name asc'])
		end

		it 'rejects keyword values that are not lowercase latin tokens' do
			expect do
				described_class.normalise_site_config(
					'pagination' => {
						'enabled' => true,
						'keywords' => {
							'now' => 'second-now'
						}
					}
				)
			end.to raise_error(ArgumentError, /must match \[a-z\]\+/)
		end

		it 'rejects duplicate keyword values' do
			expect do
				described_class.normalise_site_config(
					'pagination' => {
						'enabled' => true,
						'keywords' => {
							'day' => 'window',
							'month' => 'window'
						}
					}
				)
			end.to raise_error(ArgumentError, /must be unique/)
		end

		it 'migrates v2 legacy filter shortcuts without overriding explicit filters' do
			config = described_class.normalise_site_config(
				'pagination' => {
					'compatibility' => 'v2',
					'items' => 'products',
					'collection' => 'pages',
					'category' => 'featured',
					'tag' => 'legacy-tag',
					'filters' => {
						'category' => 'explicit-category'
					}
				}
			)

			expect(config['items']).to eq('products')
			expect(config['collection']).to eq(['pages'])
			expect(config['filters']).to include(
				'category' => 'explicit-category',
				'tag' => 'legacy-tag'
			)
			expect(config).not_to have_key('category')
			expect(config).not_to have_key('tag')
		end

		it 'ignores the v2 legacy category shortcut when category is posts' do
			config = described_class.normalise_site_config(
				'pagination' => {
					'compatibility' => 'v2',
					'category' => 'posts'
				}
			)

			expect(config['filters']).not_to have_key('category')
		end

		it 'migrates v2 autopages groups into templates.generate definitions' do
			config = described_class.normalise_site_config(
				'pagination' => {
					'compatibility' => 'v2'
				},
				'autopages' => {
					'enabled' => true,
					'categories' => {
						'enabled' => true,
						'layouts' => 'category-a.html,category-b.html',
						'title' => 'Category :cat'
					},
					'collections' => {
						'enabled' => true
					}
				}
			)

			categories_definition = config.dig('templates', 'generate').find { |entry| entry['group'] == 'category' }
			collections_definition = config.dig('templates', 'generate').find { |entry| entry['group'] == 'collection' }

			expect(categories_definition).not_to be_nil
			expect(categories_definition['layouts']).to eq(%w[category-a.html category-b.html])
			expect(categories_definition.dig('frontmatter', 'title')).to eq('Category :cat')
			expect(categories_definition).not_to have_key('silent')

			expect(collections_definition).not_to be_nil
			expect(collections_definition['layouts']).to eq(['autopage_collection.html'])
			expect(collections_definition['items']).to eq('all')
		end

		it 'normalises collection targets from delimited strings' do
			config = described_class.normalise_site_config(
				'pagination' => {
					'enabled' => true,
					'collection' => 'pages,clone'
				}
			)

			expect(config['collection']).to eq(%w[pages clone])
		end

		it 'promotes legacy nested template defaults to top-level defaults' do
			config = described_class.normalise_site_config(
				'pagination' => {
					'enabled' => true,
					'templates' => {
						'collection' => 'pages',
						'per_page' => 4
					}
				}
			)

			expect(config['collection']).to eq(['pages'])
			expect(config['per_page']).to eq(4)
		end

		it 'rejects collection target lists longer than two entries' do
			expect do
				described_class.normalise_site_config(
					'pagination' => {
						'enabled' => true,
						'collection' => 'pages,self,shadow'
					}
				)
			end.to raise_error(ArgumentError, /at most two values/)
		end

		it 'supports custom collection keywords through pagination.keywords' do
			config = described_class.normalise_site_config(
				'pagination' => {
					'enabled' => true,
					'keywords' => {
						'self' => 'same',
						'shadow' => 'mask'
					},
					'collection' => 'same,mask'
				}
			)

			expect(config['collection']).to eq(%w[self shadow])
		end

		it 'normalises group shorthand and slugify mode shorthand' do
			config = described_class.normalise_site_config(
				'pagination' => {
					'enabled' => true,
					'group' => 'category,author.name',
					'slugify' => 'pretty'
				}
			)

			expect(config['group']).to eq([
				{ 'on' => 'category' },
				{ 'on' => 'author.name' }
			])
			expect(config['slugify']).to eq({ 'mode' => 'pretty', 'lowercase' => true })
		end
	end

	describe '.normalise_template_config' do
		it 'supports nested_key_separator as a template-level syntax alias' do
			site_config = described_class.normalise_site_config(
				'pagination' => {
					'enabled' => true
				}
			)

			config = described_class.normalise_template_config(
				site_config,
				{
					'enabled' => true,
					'collection' => 'clone,pages',
					'nested_key_separator' => ':',
					'filters' => {
						'author:name' => 'Alice'
					}
				}
			)

			expect(config['separator']).to eq(':')
			expect(config['collection']).to eq(%w[clone pages])
			expect(config.dig('filters', 'author:name')).to eq('Alice')
		end

		it 'inherits site-level debug defaults' do
			site_config = described_class.normalise_site_config(
				'pagination' => {
					'enabled' => true,
					'debug' => true
				}
			)

			config = described_class.normalise_template_config(
				site_config,
				{
					'enabled' => true,
					'items' => 'posts'
				}
			)

			expect(site_config['debug']).to eq(true)
			expect(config['debug']).to eq(true)
		end

		it 'allows template-level debug to override the inherited default' do
			site_config = described_class.normalise_site_config(
				'pagination' => {
					'enabled' => true,
					'debug' => true
				}
			)

			config = described_class.normalise_template_config(
				site_config,
				{
					'enabled' => true,
					'items' => 'posts',
					'debug' => false
				}
			)

			expect(config['debug']).to eq(false)
		end

		it 'inherits site-level defaults and allows template overrides' do
			site_config = described_class.normalise_site_config(
				'pagination' => {
					'enabled' => true,
					'items' => 'products',
					'per_page' => 3,
					'collection' => 'pages',
					'slugify' => {
						'mode' => 'pretty',
						'case' => true
					}
				}
			)

			config = described_class.normalise_template_config(
				site_config,
				{
					'enabled' => true,
					'items' => 'posts',
					'group' => [
						{ 'on' => 'size', 'size' => 100, 'filter' => { 'min' => 10 } },
						'tag'
					],
					'slugify' => 'latin'
				}
			)

			expect(config['items']).to eq('posts')
			expect(config['per_page']).to eq(3)
			expect(config['collection']).to eq(['pages'])
			expect(config['group']).to eq([
				{ 'on' => 'size', 'size' => 100, 'filter' => { 'min' => 10 } },
				{ 'on' => 'tag' }
			])
			expect(config['slugify']).to eq({ 'mode' => 'latin', 'lowercase' => true })
		end
	end
end
