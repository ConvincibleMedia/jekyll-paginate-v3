# frozen_string_literal: true

RSpec.describe Jekyll::Plugins::PaginateV3::Query::Parser do
	describe '.parse' do
		it 'parses mixed string, hash, and delimited forms into canonical entries' do
			entries = described_class.parse(
				['pg|products', { 'everything' => 'docs/*|guides/*' }],
				{
					'pages' => 'pg',
					'all' => 'collections',
					'everything' => 'everything'
				},
				split_delimiter: '|'
			)

			expect(entries).to eq(
				[
					{ 'type' => 'pages', 'paths' => nil },
					{ 'type' => 'products', 'paths' => nil },
					{ 'type' => 'everything', 'paths' => %w[docs/* guides/*] }
				]
			)
		end
	end

	describe '.path_allowed?' do
		it 'supports prefix and glob path filtering' do
			expect(described_class.path_allowed?('docs/guide.md', ['docs/'])).to eq(true)
			expect(described_class.path_allowed?('docs/guide.md', ['blog/'])).to eq(false)
			expect(described_class.path_allowed?('docs/guide.md', ['docs/*'])).to eq(true)
			expect(described_class.path_allowed?('docs/guide.md', nil)).to eq(true)
		end
	end

	describe '.first_type' do
		it 'returns nil when no parsable search entries are present' do
			result = described_class.first_type('  ', {})
			expect(result).to be_nil
		end
	end

	describe '.entry_label' do
		it 'formats parsed entries with optional path filters' do
			expect(described_class.entry_label({ 'type' => 'pages', 'paths' => nil })).to eq('pages')
			expect(described_class.entry_label({ 'type' => 'products', 'paths' => ['catalog/*', 'sale/*'] })).to eq('products (catalog/*, sale/*)')
		end
	end
end
