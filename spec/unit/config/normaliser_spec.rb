# frozen_string_literal: true

RSpec.describe Jekyll::Plugins::PaginateV3::Config::Normaliser do
  describe '.normalise_site_config' do
    it 'coerces boundary values and falls back to safe defaults' do
      config = described_class.normalise_site_config(
        'pagination' => {
          'enabled' => 'yes',
          'per_page' => 0,
          'offset' => -5,
          'limit' => -3,
          'split' => nil,
          'nested_key_separator' => '/',
          'templates' => {
            'location' => '',
            'generate' => {
              'items' => 'posts',
              'index' => 'tag',
              'layout' => 'autopage_tags.html'
            }
          }
        }
      )

      expect(config['enabled']).to eq(true)
      expect(config['per_page']).to eq(1)
      expect(config['offset']).to eq(0)
      expect(config['limit']).to eq(0)
      expect(config['split']).to eq(',')
      expect(config['nested_key_separator']).to eq('.')
      expect(config.dig('templates', 'location')).to eq('pages')
      expect(config.dig('templates', 'generate')).to be_an(Array)
      expect(config.dig('templates', 'generate').length).to eq(1)
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

    it 'normalises delimited equivalent groups with a custom split delimiter' do
      config = described_class.normalise_site_config(
        'pagination' => {
          'enabled' => true,
          'split' => '|',
          'equivalents' => 'tag|tags'
        }
      )

      expect(config['equivalents']).to eq([%w[tag tags]])
    end

    it 'migrates v2 legacy shortcuts without overriding explicit filters' do
      config = described_class.normalise_site_config(
        'pagination' => {
          'compatibility' => 'v2',
          'collection' => 'products',
          'category' => 'featured',
          'tag' => 'legacy-tag',
          'filters' => {
            'category' => 'explicit-category'
          }
        }
      )

      expect(config['items']).to eq('products')
      expect(config['filters']).to include(
        'category' => 'explicit-category',
        'tag' => 'legacy-tag'
      )
      expect(config).not_to have_key('collection')
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
            'title' => 'Category :cat',
            'silent' => 'true'
          },
          'collections' => {
            'enabled' => true
          }
        }
      )

      categories_definition = config.dig('templates', 'generate').find { |entry| entry['index'] == 'category' }
      collections_definition = config.dig('templates', 'generate').find { |entry| entry['index'] == 'collection' }

      expect(categories_definition).not_to be_nil
      expect(categories_definition['layouts']).to eq(%w[category-a.html category-b.html])
      expect(categories_definition['title']).to eq('Category :cat')
      expect(categories_definition['silent']).to eq(true)

      expect(collections_definition).not_to be_nil
      expect(collections_definition['layouts']).to eq(['autopage_collection.html'])
      expect(collections_definition['items']).to eq('all')
    end
  end
end
