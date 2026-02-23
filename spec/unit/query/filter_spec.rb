# frozen_string_literal: true

RSpec.describe Jekyll::Plugins::PaginateV3::Query::Filter do
  TestCollection = Struct.new(:label)
  TestItem = Struct.new(:data, :collection)

  # Builds a minimal item object compatible with filter evaluation.
  def build_item(data, collection: nil)
    collection_object = collection.nil? ? nil : TestCollection.new(collection)
    TestItem.new(data, collection_object)
  end

  # Runs the filter engine with stable defaults used across examples.
  def apply_filters(items, filters, now_keyword: 'now', split_delimiter: ',')
    described_class.filter_items(
      items,
      filters,
      nested_separator: '.',
      equivalents: [%w[tag tags]],
      split_delimiter: split_delimiter,
      now_keyword: now_keyword
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

  it 'supports configurable now keywords for range filters' do
    current_time = DateTime.now
    items = [
      build_item({ 'title' => 'Past', 'published_at' => (current_time - 2).iso8601 }),
      build_item({ 'title' => 'Current', 'published_at' => current_time.iso8601 }),
      build_item({ 'title' => 'Future', 'published_at' => (current_time + 2).iso8601 })
    ]

    filtered = apply_filters(
      items,
      {
        'published_at' => {
          'min' => 'today - 0.5',
          'max' => 'today + 0.5'
        }
      },
      now_keyword: 'today'
    )

    expect(filtered).to eq([items[1]])
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
