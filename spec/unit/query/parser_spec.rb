# frozen_string_literal: true

RSpec.describe Jekyll::Plugins::PaginateV3::Query::Parser do
	describe '.parse' do
		it 'parses mixed string, hash, and delimited forms into internal entries' do
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
					{ 'type' => described_class::SEARCH_TYPE_PAGES, 'paths' => nil },
					{ 'type' => 'products', 'paths' => nil },
					{ 'type' => described_class::SEARCH_TYPE_EVERYTHING, 'paths' => %w[docs/* guides/*] }
				]
			)
		end

		it 'uses only renamed search keywords and releases their former collection labels' do
			entries = described_class.parse(
				%w[sitepages collections universe pages all everything],
				{
					'pages' => 'sitepages',
					'all' => 'collections',
					'everything' => 'universe'
				}
			)

			expect(entries.map { |entry| entry['type'] }).to eq([
				described_class::SEARCH_TYPE_PAGES,
				described_class::SEARCH_TYPE_ALL,
				described_class::SEARCH_TYPE_EVERYTHING,
				'pages',
				'all',
				'everything'
			])
		end

		it 'does not split scalar search definitions when split is disabled' do
			entries = described_class.parse(
				'pages,products',
				{
					'pages' => 'pages',
					'all' => 'all',
					'everything' => 'everything'
				},
				split_delimiter: false
			)

			expect(entries).to eq(
				[
					{ 'type' => 'pages,products', 'paths' => nil }
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
			expect(described_class.entry_label({ 'type' => described_class::SEARCH_TYPE_PAGES, 'paths' => nil })).to eq(described_class::SEARCH_TYPE_PAGES)
			expect(described_class.entry_label({ 'type' => 'products', 'paths' => ['catalog/*', 'sale/*'] })).to eq('products (catalog/*, sale/*)')
		end
	end
end
