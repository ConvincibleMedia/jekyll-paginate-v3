# frozen_string_literal: true

RSpec.describe Jekyll::Plugins::PaginateV3::Query::Filter do
	FilterTestCollection = Struct.new(:label)
	FilterTestItem = Struct.new(:data, :collection, :path)

	# Builds a minimal item object compatible with filter evaluation.
	def build_item(data, collection: nil, path: nil)
		collection_object = collection.nil? ? nil : FilterTestCollection.new(collection)
		FilterTestItem.new(data, collection_object, path)
	end

	# Runs the filter engine with stable defaults used across examples.
	def apply_filters(items, filters, now_keyword: 'now', today_keyword: 'today', split_delimiter: ',', log_lambda: nil, context_label: nil)
		described_class.filter_items(
			items,
			filters,
			nested_separator: '.',
			equivalents: [%w[tag tags]],
			split_delimiter: split_delimiter,
			now_keyword: now_keyword,
			today_keyword: today_keyword,
			log_lambda: log_lambda,
			context_label: context_label
		)
	end

	it 'ignores invalid filter definitions instead of failing closed' do
		items = [
			build_item({ 'title' => 'One', 'category' => 'news' }),
			build_item({ 'title' => 'Two', 'category' => 'blog' })
		]

		filtered = apply_filters(items, { 'category' => { 'unsupported' => 'value' } })
		expect(filtered).to eq(items)
	end

	it 'logs a warning when a filter definition is invalid' do
		logger = double('logger', call: nil)
		items = [
			build_item({ 'title' => 'One', 'category' => 'news' }, path: '_posts/one.md')
		]

		filtered = apply_filters(
			items,
			{ 'category' => { 'unsupported' => 'value' } },
			log_lambda: logger.method(:call),
			context_label: "Template 'index.md'"
		)

		expect(filtered).to eq(items)
		expect(logger).to have_received(:call).with(
			a_string_including("Template 'index.md': Ignoring invalid filter for key='category'"),
			'warn'
		)
	end

	it 'logs detailed debug diagnostics for key-level filtering decisions' do
		logger = double('logger', call: nil)
		items = [
			build_item({ 'title' => 'One', 'category' => 'news' }, path: '_posts/one.md'),
			build_item({ 'title' => 'Two', 'category' => 'blog' }, path: '_posts/two.md'),
			build_item({ 'title' => 'Three' }, path: '_posts/three.md')
		]

		filtered = apply_filters(
			items,
			{ 'category' => 'news' },
			log_lambda: logger.method(:call),
			context_label: "Template 'index.md'"
		)

		expect(filtered).to eq([items.first])
		expect(logger).to have_received(:call).with(
			a_string_including("Template 'index.md': Filter key='category'"),
			'debug'
		).at_least(:once)
		expect(logger).to have_received(:call).with(
			a_string_including("Filter key='category' missing key/value on: _posts/three.md"),
			'debug'
		)
		expect(logger).to have_received(:call).with(
			a_string_including("Filter key='category' excluded item sample: _posts/two.md=\"blog\""),
			'debug'
		)
	end

	it 'distinguishes strict and auto scalar matching for array values' do
		items = [
			build_item({ 'title' => 'One', 'tags' => %w[ruby jekyll] }),
			build_item({ 'title' => 'Two', 'tags' => ['jekyll'] })
		]

		strict_result = apply_filters(
			items,
			{
				'tags' => {
					'match' => 'ruby',
					'mode' => 'strict',
					'split' => false
				}
			}
		)
		auto_result = apply_filters(
			items,
			{
				'tags' => {
					'match' => 'ruby',
					'mode' => 'auto',
					'split' => false
				}
			}
		)

		expect(strict_result).to eq([])
		expect(auto_result).to eq([items.first])
	end

	it 'treats nested multi-value matches as array values for scalar modes' do
		items = [
			build_item({ 'title' => 'One', 'authors' => [{ 'name' => 'ruby' }, { 'name' => 'jekyll' }] }),
			build_item({ 'title' => 'Two', 'authors' => [{ 'name' => 'ruby' }] }),
			build_item({ 'title' => 'Three', 'authors' => [{ 'name' => 'jekyll' }] })
		]

		strict_result = apply_filters(
			items,
			{
				'authors.name' => {
					'match' => 'ruby',
					'mode' => 'strict',
					'split' => false
				}
			}
		)
		auto_result = apply_filters(
			items,
			{
				'authors.name' => {
					'match' => 'ruby',
					'mode' => 'auto',
					'split' => false
				}
			}
		)
		only_result = apply_filters(
			items,
			{
				'authors.name' => {
					'match' => 'ruby',
					'mode' => 'only',
					'split' => false
				}
			}
		)

		expect(strict_result).to eq([items[1]])
		expect(auto_result).to eq([items[0], items[1]])
		expect(only_result).to eq([items[1]])
	end

	it 'applies first-mode matching using the configured first count' do
		items = [
			build_item({ 'title' => 'One', 'contributors' => %w[alice bob] }),
			build_item({ 'title' => 'Two', 'contributors' => %w[bob alice] }),
			build_item({ 'title' => 'Three', 'contributors' => ['carol'] })
		]

		filtered = apply_filters(
			items,
			{
				'contributors' => {
					'match' => 'alice',
					'mode' => 'first',
					'first' => 1,
					'split' => false
				}
			}
		)

		expect(filtered).to eq([items.first])
	end

	it 'supports first(N) mode shorthand and defaults first to first(1)' do
		items = [
			build_item({ 'title' => 'One', 'contributors' => %w[alice bob] }),
			build_item({ 'title' => 'Two', 'contributors' => %w[bob alice] })
		]

		first_two = apply_filters(
			items,
			{
				'contributors' => {
					'match' => 'alice',
					'mode' => 'first(2)',
					'split' => false
				}
			}
		)
		first_one = apply_filters(
			items,
			{
				'contributors' => {
					'match' => 'alice',
					'mode' => 'first',
					'split' => false
				}
			}
		)

		expect(first_two).to eq(items)
		expect(first_one).to eq([items.first])
	end

	it 'treats legacy firstN mode shorthand as invalid' do
		items = [
			build_item({ 'title' => 'One', 'contributors' => %w[alice bob] }),
			build_item({ 'title' => 'Two', 'contributors' => %w[bob alice] })
		]

		filtered = apply_filters(
			items,
			{
				'contributors' => {
					'match' => 'alice',
					'mode' => 'first2',
					'split' => false
				}
			}
		)

		expect(filtered).to eq(items)
	end

	it 'supports per-filter split delimiters independent of global split' do
		items = [
			build_item({ 'title' => 'One', 'audience' => 'news|alerts' }),
			build_item({ 'title' => 'Two', 'audience' => 'news' })
		]

		filtered = apply_filters(
			items,
			{
				'audience' => {
					'match' => 'alerts',
					'split' => '|'
				}
			}
		)

		expect(filtered).to eq([items.first])
	end

	it 'supports configurable today keywords for range filters' do
		current_time = DateTime.now
		start_of_today = DateTime.new(current_time.year, current_time.month, current_time.day, 0, 0, 0, current_time.offset)
		items = [
			build_item({ 'title' => 'Two Days Ago', 'published_at' => (start_of_today - 2 + Rational(43_200, 86_400)).iso8601 }),
			build_item({ 'title' => 'Yesterday', 'published_at' => (start_of_today - 1 + Rational(43_200, 86_400)).iso8601 }),
			build_item({ 'title' => 'Today End', 'published_at' => (start_of_today + Rational(86_399, 86_400)).iso8601 }),
			build_item({ 'title' => 'Tomorrow', 'published_at' => (start_of_today + 1 + Rational(43_200, 86_400)).iso8601 })
		]

		filtered = apply_filters(
			items,
			{
				'published_at' => {
					'min' => 'daystart-1',
					'max' => 'daystart'
				}
			},
			today_keyword: 'daystart'
		)

		expect(filtered).to eq([items[1], items[2]])
	end

	it 'supports now keyword offsets in whole seconds' do
		current_time = DateTime.now
		items = [
			build_item({ 'title' => 'Past', 'published_at' => (current_time - Rational(7_200, 86_400)).iso8601 }),
			build_item({ 'title' => 'Current', 'published_at' => current_time.iso8601 }),
			build_item({ 'title' => 'Future', 'published_at' => (current_time + Rational(7_200, 86_400)).iso8601 })
		]

		filtered = apply_filters(
			items,
			{
				'published_at' => {
					'min' => 'now - 3600',
					'max' => 'now + 3600'
				}
			}
		)

		expect(filtered).to eq([items[1]])
	end

	it 'treats non-integer keyword offsets as invalid range filters' do
		current_time = DateTime.now
		items = [
			build_item({ 'title' => 'Current', 'published_at' => current_time.iso8601 }),
			build_item({ 'title' => 'Future', 'published_at' => (current_time + 1).iso8601 })
		]

		filtered_today = apply_filters(
			items,
			{
				'published_at' => {
					'min' => 'today - 0.5',
					'max' => 'today + 0.5'
				}
			}
		)

		filtered_now = apply_filters(
			items,
			{
				'published_at' => {
					'min' => 'now - 0.5',
					'max' => 'now + 0.5'
				}
			}
		)

		expect(filtered_today).to eq(items)
		expect(filtered_now).to eq(items)
	end

	it 'ignores invalid mixed-type range definitions gracefully' do
		items = [
			build_item({ 'title' => 'One', 'rating' => 1 }),
			build_item({ 'title' => 'Two', 'rating' => 2 })
		]

		filtered = apply_filters(
			items,
			{
				'rating' => {
					'min' => 1,
					'max' => '2026-01-01T00:00:00+00:00'
				}
			}
		)

		expect(filtered).to eq(items)
	end

	it 'supports inclusive and exclusive range mode boundaries' do
		items = [
			build_item({ 'title' => 'One', 'rating' => 1 }),
			build_item({ 'title' => 'Two', 'rating' => 2 }),
			build_item({ 'title' => 'Three', 'rating' => 3 })
		]

		min_exclusive = apply_filters(
			items,
			{
				'rating' => {
					'min' => 2,
					'max' => 3,
					'mode' => 'min-exclusive max-inclusive'
				}
			}
		)
		max_exclusive = apply_filters(
			items,
			{
				'rating' => {
					'min' => 1,
					'max' => 3,
					'mode' => 'min-inclusive max-exclusive'
				}
			}
		)

		expect(min_exclusive).to eq([items[2]])
		expect(max_exclusive).to eq([items[0], items[1]])
	end

	it 'treats invalid range mode definitions as invalid filters' do
		items = [
			build_item({ 'title' => 'One', 'rating' => 1 }),
			build_item({ 'title' => 'Two', 'rating' => 2 })
		]

		filtered = apply_filters(
			items,
			{
				'rating' => {
					'min' => 1,
					'max' => 2,
					'mode' => 'bad-mode'
				}
			}
		)

		expect(filtered).to eq(items)
	end

	it 'supports filtering by the synthetic collection key' do
		items = [
			build_item({ 'title' => 'Site Page' }),
			build_item({ 'title' => 'Product One' }, collection: 'products'),
			build_item({ 'title' => 'Guide One' }, collection: 'guides')
		]

		filtered = apply_filters(items, { 'collection' => 'products' })
		expect(filtered).to eq([items[1]])
	end
end
