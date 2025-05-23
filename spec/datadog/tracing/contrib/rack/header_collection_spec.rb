require 'datadog/tracing/contrib/rack/header_collection'

RSpec.describe Datadog::Tracing::Contrib::Rack::Header::RequestHeaderCollection do
  subject(:collection) { described_class.new env }
  let(:env) { {} }

  describe '#get' do
    context 'when header exists in env' do
      let(:env) do
        {
          'HTTP_X_FORWARDED_FOR' => 'me'
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
          'HTTP_USER_AGENT' => 'test'
        }
      end

      it 'returns nil' do
        expect(collection.get('X-Forwarded-For')).to be_nil
      end
    end

    context 'when Content-Type and Content-Length headers exist in env' do
      let(:env) do
        {
          'CONTENT_TYPE' => 'application/json',
          'CONTENT_LENGTH' => '120'
        }
      end

      it 'returns header value' do
        expect(collection.get('Content-Type')).to eq('application/json')
        expect(collection.get('Content-Length')).to eq('120')
      end

      it 'returns header value regardless of letter casing in the name' do
        expect(collection.get('content-type')).to eq('application/json')
        expect(collection.get('content-length')).to eq('120')
      end
    end
  end
end
