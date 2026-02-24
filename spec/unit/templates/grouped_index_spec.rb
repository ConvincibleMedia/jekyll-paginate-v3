# frozen_string_literal: true

RSpec.describe Jekyll::Plugins::PaginateV3::Templates::GroupedIndex do
  TestCollection = Struct.new(:label)
  TestItem = Struct.new(:data, :collection)

  # Builds a minimal item object compatible with grouped indexing evaluation.
  def build_item(data, collection: nil)
    collection_object = collection.nil? ? nil : TestCollection.new(collection)
    TestItem.new(data, collection_object)
  end

  # Runs grouped indexing with stable defaults.
  def build_entries(key:, group:, items:, now_keyword: 'now', today_keyword: 'today')
    described_class.new(
      key: key,
      raw_group: group,
      items: items,
      nested_separator: '.',
      split_delimiter: ',',
      equivalents: [%w[tag tags]],
      now_keyword: now_keyword,
      today_keyword: today_keyword
    ).build_entries
  end

  it 'builds numeric grouped entries with inclusive first bound and exclusive later mins' do
    items = [
      build_item({ 'size' => 23 }),
      build_item({ 'size' => 156 }),
      build_item({ 'size' => 200 })
    ]

    entries = build_entries(key: 'size', group: 100, items: items)

    expect(entries.length).to eq(2)
    expect(entries[0].dig('values', 'size')).to eq('100')
    expect(entries[0].dig('filters', 'size')).to include('min' => 0.0, 'max' => 100.0, 'mode' => 'min-inclusive max-inclusive')
    expect(entries[1].dig('values', 'size')).to eq('200')
    expect(entries[1].dig('filters', 'size')).to include('min' => 100.0, 'max' => 200.0, 'mode' => 'min-exclusive max-inclusive')
  end

  it 'supports numeric total with an open-ended final group' do
    items = [
      build_item({ 'size' => 350 })
    ]

    entries = build_entries(
      key: 'size',
      group: {
        'start' => 0,
        'step' => 100,
        'total' => 2,
        'empty' => true
      },
      items: items
    )

    expect(entries.length).to eq(2)
    expect(entries[0].dig('filters', 'size')).to include('min' => 0.0, 'max' => 100.0)
    expect(entries[1].dig('filters', 'size')).to include('min' => 100.0, 'mode' => 'min-exclusive')
    expect(entries[1].dig('filters', 'size')).not_to have_key('max')
    expect(entries[1].dig('group', 'end')).to be_nil
  end

  it 'supports datetime calendar durations for grouped steps' do
    items = [
      build_item({ 'published_on' => '2026-12-15' }),
      build_item({ 'published_on' => '2027-02-11' })
    ]

    entries = build_entries(
      key: 'published_on',
      group: {
        'start' => '2026-12-12',
        'step' => 'month(2)'
      },
      items: items
    )

    expect(entries.length).to eq(1)
    expect(entries[0].dig('filters', 'published_on', 'mode')).to eq('min-inclusive max-inclusive')
    expect(entries[0].dig('token_values', 'published_on', 'permalink')).to eq('2027-02-12')
  end

  it 'supports bare datetime step keywords as implicit (1)' do
    items = [
      build_item({ 'published_on' => '2026-06-10' }),
      build_item({ 'published_on' => '2027-02-01' })
    ]

    entries = build_entries(
      key: 'published_on',
      group: {
        'start' => '2026-01-01',
        'step' => 'year'
      },
      items: items
    )

    expect(entries.length).to eq(2)
    expect(entries[0].dig('values', 'published_on')).to include('2027-01-01')
    expect(entries[1].dig('values', 'published_on')).to include('2028-01-01')
  end

  it 'supports alphabetic grouped ranges and an optional other group' do
    items = [
      build_item({ 'title' => 'Apple' }),
      build_item({ 'title' => 'Banana' }),
      build_item({ 'title' => '9lives' })
    ]

    entries = build_entries(
      key: 'title',
      group: {
        'start' => 'aa',
        'step' => 1,
        'other' => '0-9'
      },
      items: items
    )

    other_entry = entries.find { |entry| entry.dig('group', 'other') }
    expect(other_entry).not_to be_nil
    expect(other_entry.dig('values', 'title')).to eq('0-9')
    expect(other_entry.dig('filters', 'title')).to eq('/^[^a-z]/i')
    expect(entries.last).to eq(other_entry)
  end

  it 'defaults alphabetic hash start to a and requires step' do
    items = [
      build_item({ 'title' => 'banana' })
    ]

    entries = build_entries(
      key: 'title',
      group: {
        'step' => 1,
        'empty' => true
      },
      items: items
    )

    expect(entries.first.dig('group', 'start')).to eq('a')
    expect do
      build_entries(
        key: 'title',
        group: {
          'start' => 'aa'
        },
        items: items
      )
    end.to raise_error(ArgumentError, /group.step/)
  end

  it 'raises when implied automatic groups exceed the safety cap' do
    items = [
      build_item({ 'size' => 250 })
    ]

    expect do
      build_entries(
        key: 'size',
        group: {
          'start' => 0,
          'step' => 1
        },
        items: items
      )
    end.to raise_error(ArgumentError, /more than 100 groups/)
  end
end
