# frozen_string_literal: true

RSpec.describe Jekyll::Plugins::PaginateV3::Query::Sorter do
  TestCollection = Struct.new(:label)
  TestItem = Struct.new(:data, :collection)

  # Builds a minimal item object compatible with sorter evaluation.
  def build_item(data, collection: nil)
    collection_object = collection.nil? ? nil : TestCollection.new(collection)
    TestItem.new(data, collection_object)
  end

  # Runs the sorter with stable defaults used across examples.
  def apply_sort(items, sort_definition, split_delimiter: ',')
    described_class.apply(
      items,
      sort_definition,
      nested_separator: '.',
      equivalents: [%w[tag tags]],
      split_delimiter: split_delimiter
    )
  end

  it 'preserves input order when all sort keys tie' do
    items = [
      build_item({ 'title' => 'First', 'priority' => 1 }),
      build_item({ 'title' => 'Second', 'priority' => 1 }),
      build_item({ 'title' => 'Third', 'priority' => 1 })
    ]

    sorted = apply_sort(items, 'priority asc')
    expect(sorted).to eq(items)
  end

  it 'orders mixed scalar types by rank before value comparison' do
    items = [
      build_item({ 'value' => 'alpha' }),
      build_item({ 'value' => 2 }),
      build_item({ 'value' => false }),
      build_item({ 'value' => true })
    ]

    sorted = apply_sort(items, 'value asc')
    expect(sorted.map { |item| item.data['value'] }).to eq([true, false, 2, 'alpha'])
  end

  it 'places empty values first when configured' do
    items = [
      build_item({ 'title' => 'Bob', 'owner' => { 'name' => 'Bob' } }),
      build_item({ 'title' => 'No Owner' }),
      build_item({ 'title' => 'Ada', 'owner' => { 'name' => 'Ada' } })
    ]

    sorted = apply_sort(items, 'owner.name asc empty:first')
    expect(sorted.map { |item| item.data['title'] }).to eq(['No Owner', 'Ada', 'Bob'])
  end

  it 'supports sorting by the synthetic collection field' do
    items = [
      build_item({ 'title' => 'Site Page' }),
      build_item({ 'title' => 'Product' }, collection: 'products'),
      build_item({ 'title' => 'Guide' }, collection: 'guides')
    ]

    sorted = apply_sort(items, ['collection asc', 'title asc'])
    expect(sorted.map { |item| item.data['title'] }).to eq(['Guide', 'Product', 'Site Page'])
  end

  it 'parses delimited sort strings with a custom split delimiter' do
    instructions = described_class.parse('priority desc|title asc', split_delimiter: '|')

    expect(instructions).to eq(
      [
        { 'field' => 'priority', 'direction' => 'desc', 'empty' => 'last' },
        { 'field' => 'title', 'direction' => 'asc', 'empty' => 'last' }
      ]
    )
  end
end
