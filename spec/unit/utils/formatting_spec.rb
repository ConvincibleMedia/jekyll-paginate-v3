# frozen_string_literal: true

RSpec.describe Jekyll::Plugins::PaginateV3::Utils do
  describe '.replace_tokens' do
    it 'prefers the longest placeholder name when placeholders overlap' do
      output = described_class.replace_tokens(
        '/page:foobar:foo:bar',
        {
          'foo' => 'small',
          'foob' => 'large',
          'bar' => 'tail'
        }
      )

      expect(output).to eq('/pagelargearsmalltail')
    end

    it 'returns the original template when token map is not a hash' do
      output = described_class.replace_tokens('/page:foo', nil)
      expect(output).to eq('/page:foo')
    end
  end
end
