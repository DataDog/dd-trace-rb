require 'datadog/tracing/contrib/support/spec_helper'
require 'opensearch'

require 'datadog'
require 'datadog/tracing/contrib/opensearch/quantize'

RSpec.describe Datadog::Tracing::Contrib::OpenSearch::Quantize do
  describe '#format_url' do
    shared_examples_for 'a quantized URL' do |url, expected_url|
      subject(:quantized_url) { described_class.format_url(url) }

      it { is_expected.to eq(expected_url) }
    end

    context 'when the URL contains an ID' do
      it_behaves_like 'a quantized URL', '/my/thing/1', '/my/thing/?'
      it_behaves_like 'a quantized URL', '/my/thing/1/', '/my/thing/1/'
      it_behaves_like 'a quantized URL', '/my/thing/1/is/cool', '/my/thing/1/is/cool'
      it_behaves_like 'a quantized URL', '/my/thing/1two3/z', '/my/thing/1two3/z'
      it_behaves_like 'a quantized URL', '/my/thing/1two3/z/', '/my/thing/1two3/z/'
      it_behaves_like 'a quantized URL', '/my/thing/1two3/abc', '/my/thing/1two3/abc'
      it_behaves_like 'a quantized URL', '/my/thing/1two3/abc/', '/my/thing/1two3/abc/'
      it_behaves_like 'a quantized URL', '/my/thing231/1two3/abc/', '/my/thing231/1two3/abc/'
    end

    context 'when the URL looks like an index' do
      it_behaves_like 'a quantized URL', '/my123456/thing', '/my123456/thing'
      it_behaves_like 'a quantized URL', '/my123456more/thing', '/my123456more/thing'
      it_behaves_like 'a quantized URL', '/my123456and789/thing', '/my123456and789/thing'
    end

    context 'when the URL has both an index and ID' do
      it_behaves_like 'a quantized URL', '/my123/thing/456789', '/my123/thing/?'
    end
  end

  describe '#format_body' do
    shared_examples_for 'a quantized body' do |body, expected_body|
      subject(:quantized_body) { described_class.format_body(body, options) }

      it { is_expected.to eq(expected_body) }
    end

    let(:options) { {} }

    context 'when given the option' do
      describe ':show with' do
        context 'an Array of attributes' do
          let(:options) { { show: [:title] } }

          it_behaves_like 'a quantized body',
            '{"query":{"match":{"title":"test","subtitle":"test"}}}',
            '{"query":{"match":{"title":"test","subtitle":"?"}}}'
        end

        context ':all' do
          let(:options) { { show: :all } }

          it_behaves_like 'a quantized body',
            '{"query":{"match":{"title":"test","subtitle":"test"}}}',
            '{"query":{"match":{"title":"test","subtitle":"test"}}}'
          it_behaves_like 'a quantized body',
            '[{"foo":"foo"},{"bar":"bar"}]',
            '[{"foo":"foo"},{"bar":"bar"}]'
          it_behaves_like 'a quantized body',
            '["foo","bar"]',
            '["foo","bar"]'
        end
      end

      describe ':exclude with' do
        context 'an Array of attributes' do
          let(:options) { { exclude: [:title] } }

          it_behaves_like 'a quantized body',
            '{"query":{"match":{"title":"test","subtitle":"test"}}}',
            '{"query":{"match":{"subtitle":"?"}}}'
        end
      end
    end

    context 'when the body' do
      context 'is in a format for' do
        describe 'MGet' do
          it_behaves_like 'a quantized body',
            '{"ids":["1","2","3"]}',
            '{"ids":["?"]}'
        end

        describe 'Search' do
          it_behaves_like 'a quantized body',
            '{"query":{"match":{"title":"test"}}}',
            '{"query":{"match":{"title":"?"}}}'
        end

        # rubocop:disable Layout/LineLength
        describe 'MSearch' do
          it_behaves_like 'a quantized body',
            "{}\n{\"query\":{\"match_all\":{}}}\n{\"index\":\"myindex\",\"type\":\"mytype\"}\n{\"query\":{\"query_string\":{\"query\":\"\\\"test\\\"\"}}}\n{\"search_type\":\"count\"}\n{\"aggregations\":{\"published\":{\"terms\":{\"field\":\"published\"}}}}\n",
            "{}\n{\"query\":{\"match_all\":{}}}\n{\"index\":\"?\",\"type\":\"?\"}\n{\"query\":{\"query_string\":{\"query\":\"?\"}}}\n{\"search_type\":\"?\"}\n{\"aggregations\":{\"published\":{\"terms\":{\"field\":\"?\"}}}}"
        end

        describe 'Bulk' do
          it_behaves_like 'a quantized body',
            "{\"index\":{\"_index\":\"myindex\",\"_type\":\"mytype\",\"_id\":1}}\n{\"title\":\"foo\"}\n{\"index\":{\"_index\":\"myindex\",\"_type\":\"mytype\",\"_id\":2}}\n{\"title\":\"foo\"}\n",
            "{\"index\":{\"_index\":\"myindex\",\"_type\":\"mytype\",\"_id\":1}}\n{\"title\":\"?\"}\n{\"index\":{\"_index\":\"myindex\",\"_type\":\"mytype\",\"_id\":2}}\n{\"title\":\"?\"}"
        end
        # rubocop:enable Layout/LineLength
      end
    end
  end
end
