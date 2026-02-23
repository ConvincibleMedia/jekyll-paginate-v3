# frozen_string_literal: true

RSpec.describe Jekyll::Plugins::PaginateV3::Utils do
  describe '.fetch_nested_values' do
    it 'reads nested values through arrays of hashes' do
      data = {
        'product' => {
          'variants' => [
            { 'name' => 'Small', 'size' => 34 },
            { 'name' => 'Large', 'size' => 40 }
          ]
        }
      }

      values = described_class.fetch_nested_values(data, 'product.variants.size', '.', {})
      expect(values).to eq([34, 40])
    end

    it 'applies equivalent keys only on matching full nested paths' do
      data = {
        'product' => {
          'tags' => ['ruby']
        },
        'tags' => ['jekyll']
      }
      equivalents = described_class.build_equivalent_lookup(
        [
          %w[tag tags],
          ['product.tag', 'product.tags']
        ]
      )

      product_values = described_class.fetch_nested_values(data, 'product.tag', '.', equivalents)
      root_values = described_class.fetch_nested_values(data, 'tag', '.', equivalents)

      expect(product_values).to eq(['ruby'])
      expect(root_values).to eq(['jekyll'])
    end
  end
end
