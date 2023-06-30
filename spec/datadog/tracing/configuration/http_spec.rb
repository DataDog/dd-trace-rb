require 'spec_helper'

require 'datadog/tracing/configuration/http'

RSpec.describe Datadog::Tracing::Configuration::HTTP::HeaderTags do
  subject(:http_header_tags) { described_class.new(header_tags) }
  let(:header_tags) { [header_tag] }
  let(:headers) { { 'my-header' => 'MY-VALUE', 'another-header' => 'another-value' } }

  shared_context 'a header tag processor' do
    context 'with simple element' do
      let(:header_tag) { 'my-header' }

      it 'uses the internal pattern for request/response tag name' do
        is_expected.to contain_exactly(["http.#{direction}.headers.my-header", 'MY-VALUE'])
      end

      context 'with multiple tags' do
        let(:header_tags) { ['my-header', 'another-header'] }

        it 'captures all headers' do
          is_expected.to contain_exactly(
            ["http.#{direction}.headers.my-header", 'MY-VALUE'],
            ["http.#{direction}.headers.another-header", 'another-value']
          )
        end
      end

      it '#to_s returns the configured object in the original format' do
        expect(http_header_tags.to_s).to eq('my-header')
      end
    end

    context 'with custom tag name' do
      let(:header_tag) { 'my-header:my-tag' }

      it 'respects the custom name' do
        is_expected.to contain_exactly(['my-tag', 'MY-VALUE'])
      end

      context 'and multiple `:` characters' do
        let(:header_tag) { 'my-header:my:tag' }

        it 'allows for `:` in the span tag portion' do
          is_expected.to contain_exactly(['my:tag', 'MY-VALUE'])
        end
      end

      context 'with multiple tags' do
        let(:header_tags) { ['my-header:my-tag', 'another-header:another-tag'] }

        it 'captures all headers' do
          is_expected.to contain_exactly(['my-tag', 'MY-VALUE'], ['another-tag', 'another-value'])
        end

        it '#to_s returns the configured object in the original format' do
          expect(http_header_tags.to_s).to eq('my-header:my-tag,another-header:another-tag')
        end
      end

      it '#to_s returns the configured object in the original format' do
        expect(http_header_tags.to_s).to eq('my-header:my-tag')
      end
    end

    context 'with special characters' do
      let(:header_tag) { 'my-header:My,Header-1_2.3/4@5' }

      it 'escapes special characters and lower cases the tag name' do
        is_expected.to contain_exactly(['my_header-1_2.3/4_5', 'MY-VALUE'])
      end

      it '#to_s returns the configured object in the original format' do
        expect(http_header_tags.to_s).to eq('my-header:My,Header-1_2.3/4@5')
      end
    end
  end

  context 'with request headers' do
    subject(:request) { http_header_tags.request_tags(header_collection) }
    let(:direction) { 'request' }

    let(:header_collection) do
      Datadog::Tracing::Contrib::Rack::Header::RequestHeaderCollection.new(
        headers.map do |key, value|
          [Datadog::Tracing::Contrib::Rack::Header.to_rack_header(key), value]
        end.to_h
      )
    end

    it_behaves_like 'a header tag processor'
  end

  context 'with response headers' do
    subject(:response) { http_header_tags.response_tags(headers) }
    let(:direction) { 'response' }

    it_behaves_like 'a header tag processor'
  end
end
