# frozen_string_literal: true

RSpec.describe Jekyll::Plugins::PaginateV3::Support::LooseScalar do
	it 'parses loose booleans from values and strings' do
		expect(described_class.boolean(true)).to eq(true)
		expect(described_class.boolean(false)).to eq(false)
		expect(described_class.boolean(' TRUE ')).to eq(true)
		expect(described_class.boolean('false')).to eq(false)
		expect(described_class.boolean('maybe')).to be_nil
	end

	it 'parses integer and float numbers from loose strings' do
		expect(described_class.number(3)).to eq(3)
		expect(described_class.number(1.5)).to eq(1.5)
		expect(described_class.number(' 4 ')).to eq(4)
		expect(described_class.number('1.25')).to eq(1.25)
		expect(described_class.number('cat')).to be_nil
	end

	it 'treats whole floats as integral numbers' do
		expect(described_class.integral_number?(1)).to eq(true)
		expect(described_class.integral_number?('1.0')).to eq(true)
		expect(described_class.integral_number?(1.5)).to eq(false)
	end

	it 'parses date-like values into datetimes' do
		expect(described_class.date(Date.new(2026, 1, 1))).to be_a(DateTime)
		expect(described_class.datetime('2026-01-01')).to be_a(DateTime)
		expect(described_class.datetime('not a date')).to be_nil
	end

	it 'normalises comparable values using numeric and datetime coercion' do
		expect(described_class.comparable(' 4 ')).to eq(4)
		expect(described_class.comparable('1.25')).to eq(1.25)
		expect(described_class.comparable('2026-01-01')).to be_a(DateTime)
		expect(described_class.comparable(' hello ')).to eq('hello')
		expect(described_class.comparable(Object.new, must_cast: true)).to be_nil
	end

	it 'treats integers and floats as comparable values' do
		expect(described_class.comparable_values?(1, 1.0)).to eq(true)
		expect(described_class.comparable_values?(DateTime.parse('2026-01-01'), Date.parse('2026-01-01').to_datetime)).to eq(true)
		expect(described_class.comparable_values?(1, 'cat')).to eq(false)
	end
end
