require 'spec_helper'

require 'datadog/tracing/configuration/http'
require 'datadog/core/utils/hash'

RSpec.describe Datadog::Tracing::Configuration::HTTP::HeaderTags do
  let(:http_header_tags) { described_class.new(header_tags) }
  let(:header_tags) { [header_tag] }
  let(:headers) { { 'My-Header' => 'MY-VALUE', 'Another-Header' => 'another-value' } }
  let(:case_insensitive_hash) { Datadog::Core::Utils::Hash::CaseInsensitiveWrapper.new(headers) }

  shared_context 'a header tag processor' do
    context 'with simple element' do
      let(:header_tag) { 'my-header' }

      it 'uses the internal pattern for request/response tag name' do
        is_expected.to contain_exactly(["http.#{direction}.headers.my-header", 'MY-VALUE'])
      end

      context "with a trailing ':'" do
        let(:header_tag) { 'my-header:' }

        it 'uses the internal pattern for request/response tag name' do
          is_expected.to contain_exactly(["http.#{direction}.headers.my-header", 'MY-VALUE'])
        end
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
    subject(:request) { http_header_tags.request_tags(case_insensitive_hash) }
    let(:direction) { 'request' }

    it_behaves_like 'a header tag processor'
  end

  context 'with response headers' do
    subject(:response) { http_header_tags.response_tags(case_insensitive_hash) }
    let(:direction) { 'response' }

    it_behaves_like 'a header tag processor'
  end
end
