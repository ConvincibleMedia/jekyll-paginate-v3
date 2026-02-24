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
            'defaults' => {
              'per_page' => 0,
              'offset' => -5,
              'limit' => -3
            },
            'generate' => {
              'items' => 'posts',
              'index' => 'tag',
              'layout' => 'autopage_tags.html'
            }
          }
        }
      )

      expect(config['enabled']).to eq(true)
      expect(config.dig('templates', 'defaults', 'per_page')).to eq(1)
      expect(config.dig('templates', 'defaults', 'offset')).to eq(0)
      expect(config.dig('templates', 'defaults', 'limit')).to eq(0)
      expect(config.dig('syntax', 'split')).to eq(',')
      expect(config.dig('syntax', 'separator')).to eq('.')
      expect(config.dig('keywords', 'now')).to eq('now')
      expect(config.dig('keywords', 'today')).to eq('today')
      expect(config.dig('templates', 'location')).to eq('pages')
      expect(config.dig('templates', 'generate')).to be_an(Array)
      expect(config.dig('templates', 'generate').length).to eq(1)
    end

    it 'uses sort_field and sort_reverse when sort is omitted' do
      config = described_class.normalise_site_config(
        'pagination' => {
          'enabled' => true,
          'templates' => {
            'defaults' => {
              'sort' => nil,
              'sort_field' => 'title',
              'sort_reverse' => true
            }
          }
        }
      )

      expect(config.dig('templates', 'defaults', 'sort')).to eq(['title desc'])
    end

    it 'supports variable per-page definitions as arrays' do
      config = described_class.normalise_site_config(
        'pagination' => {
          'enabled' => true,
          'templates' => {
            'defaults' => {
              'per_page' => [3, 1, 0, -4]
            }
          }
        }
      )

      expect(config.dig('templates', 'defaults', 'per_page')).to eq([3, 1, 1, 1])
    end

    it 'supports variable per-page definitions as delimited strings' do
      config = described_class.normalise_site_config(
        'pagination' => {
          'enabled' => true,
          'syntax' => {
            'split' => '|'
          },
          'templates' => {
            'defaults' => {
              'per_page' => '4|2|1'
            }
          }
        }
      )

      expect(config.dig('templates', 'defaults', 'per_page')).to eq([4, 2, 1])
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

      expect(config.dig('templates', 'defaults', 'items')).to eq('products')
      expect(config.dig('templates', 'defaults', 'filters')).to include(
        'category' => 'explicit-category',
        'tag' => 'legacy-tag'
      )
      expect(config.dig('templates', 'defaults')).not_to have_key('collection')
      expect(config.dig('templates', 'defaults')).not_to have_key('category')
      expect(config.dig('templates', 'defaults')).not_to have_key('tag')
    end

    it 'ignores the v2 legacy category shortcut when category is posts' do
      config = described_class.normalise_site_config(
        'pagination' => {
          'compatibility' => 'v2',
          'category' => 'posts'
        }
      )

      expect(config.dig('templates', 'defaults', 'filters')).not_to have_key('category')
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
