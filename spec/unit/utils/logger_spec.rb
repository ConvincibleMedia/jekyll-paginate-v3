# frozen_string_literal: true

RSpec.describe Jekyll::Plugins::PaginateV3::Utils::Logger do
	let(:jekyll_logger) { double('Jekyll logger', info: nil, warn: nil, error: nil) }

	before do
		allow(Jekyll).to receive(:logger).and_return(jekyll_logger)
	end

	it 'suppresses debug messages when debug mode is disabled' do
		logger = described_class.new(debug_enabled: false)

		logger.call('normal info')
		logger.call('debug details', 'debug')

		expect(jekyll_logger).to have_received(:info).with('Pagination:', 'normal info')
		expect(jekyll_logger).not_to have_received(:info).with('Pagination:', '[debug] debug details')
	end

	it 'emits debug messages when debug mode is enabled' do
		logger = described_class.new(debug_enabled: true)

		logger.call('debug details', 'debug')

		expect(jekyll_logger).to have_received(:info).with('Pagination:', '[debug] debug details')
	end

	it 'routes warn and error levels to matching logger methods' do
		logger = described_class.new(debug_enabled: true)

		logger.call('watch this', 'warn')
		logger.call('boom', 'error')

		expect(jekyll_logger).to have_received(:warn).with('Pagination:', 'watch this')
		expect(jekyll_logger).to have_received(:error).with('Pagination:', 'boom')
	end
end
