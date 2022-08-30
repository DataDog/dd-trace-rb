require 'datadog/core/header_collection'

RSpec.describe Datadog::Core::HeaderCollection do
  subject(:collection) { described_class.from_hash hash }
  let(:hash) { {} }

  describe '#get' do
    context 'when header exists in env' do
      let(:hash) do
        {
          'X-Forwarded-For' => 'me'
        }
      end

      it 'returns header value' do
        expect(collection.get('X-Forwarded-For')).to eq('me')
      end

      it 'returns header value regardless of letter casing in the name' do
        expect(collection.get('x-forwarded-for')).to eq('me')
      end
    end

    context 'when header does not exists in env' do
      let(:env) do
        {
          'User-Agent' => 'test'
        }
      end

      it 'returns nil' do
        expect(collection.get('X-Forwarded-For')).to be_nil
      end
    end
  end
end
