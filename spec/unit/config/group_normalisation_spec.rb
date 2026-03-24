# frozen_string_literal: true

RSpec.describe Jekyll::Plugins::PaginateV3::Config::Normaliser do
	describe '.normalise_site_config' do
		it 'treats documented bunch as an alias for grouped range configuration' do
			config = described_class.normalise_site_config(
				'pagination' => {
					'enabled' => true,
					'group' => [
						{
							'on' => 'size',
							'bunch' => {
								'step' => 100
							}
						},
						{
							'on' => 'title',
							'bunch' => {
								'start' => 'a',
								'step' => 13,
								'other' => '0-9'
							}
						}
					]
				}
			)

			expect(config['group']).to eq(
				[
					{
						'on' => 'size',
						'size' => {
							'step' => 100
						}
					},
					{
						'on' => 'title',
						'size' => {
							'start' => 'a',
							'step' => 13,
							'other' => '0-9'
						}
					}
				]
			)
		end
	end
end
