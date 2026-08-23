# frozen_string_literal: true

RSpec.describe Jekyll::Plugins::PaginateV3::Utils do
	describe '.validate_resolved_permalink!' do
		it 'accepts site-local paths with route-safe Unicode and extensions' do
			%w[/ /guides/c-sharp/ /guides/café/ /feed.json].each do |permalink|
				expect(
					described_class.validate_resolved_permalink!(permalink, context: 'spec output')
				).to eq(permalink)
			end
		end

		it 'rejects unsafe literal and encoded URL structures' do
			invalid_permalinks = [
				'relative/path/',
				'//example.test/path/',
				'/https://example.test/path/',
				'/has space/',
				'/query?value/',
				'/fragment#value/',
				'/windows\\path/',
				'/safe/../escape/',
				'/safe/%2e%2e/escape/',
				'/safe/%252e%252e/escape/',
				'/safe/%2fescape/',
				'/safe/%23fragment/'
			]

			invalid_permalinks.each do |permalink|
				expect do
					described_class.validate_resolved_permalink!(permalink, context: 'spec output')
				end.to raise_error(ArgumentError, /Invalid resolved permalink/)
			end
		end
	end

	describe '.validate_output_destination!' do
		it 'accepts contained destinations and rejects paths outside site.dest' do
			destination_root = File.expand_path('spec-output')
			site = Struct.new(:dest).new(destination_root)
			item = instance_double(Jekyll::Page)

			allow(item).to receive(:destination).with(destination_root).and_return(File.join(destination_root, 'guides', 'index.html'))
			expect(
				described_class.validate_output_destination!(item, site: site, context: 'spec output')
			).to eq(File.join(destination_root, 'guides', 'index.html'))

			allow(item).to receive(:destination).with(destination_root).and_return(File.expand_path('../outside.html', destination_root))
			expect do
				described_class.validate_output_destination!(item, site: site, context: 'spec output')
			end.to raise_error(ArgumentError, /falls outside site destination/)
		end
	end
end
