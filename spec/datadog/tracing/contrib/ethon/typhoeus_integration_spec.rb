require 'datadog/tracing/contrib/support/spec_helper'

require 'datadog/tracing/contrib/ethon/shared_examples'
require 'datadog/tracing/contrib/ethon/integration_context'
require 'spec/datadog/tracing/contrib/ethon/support/thread_helpers'

RSpec.describe Datadog::Tracing::Contrib::Ethon do
  before { skip unless ENV['TEST_DATADOG_INTEGRATION'] }

  before(:context) do
    # Ethon will lazily initialize LibCurl,
    # which spans a leaky native thread.
    #
    # We initialize LibCurl eagerly here, to allow us
    # to tag only the offending thread in isolation.
    # The simplest way to trigger the thread creation
    # is to create a new Ethon::Easy object.
    #
    # This allows us to still ensure that the integration
    # itself is leak-free.
    EthonSupport.ethon_easy_new
  end

  context 'with Typhoeus request' do
    subject(:request) { Typhoeus::Request.new(url, timeout: timeout).run }

    it_behaves_like 'instrumented request'
  end

  context 'with single Hydra request' do
    subject(:request) do
      hydra = Typhoeus::Hydra.new
      request = Typhoeus::Request.new(url, timeout: timeout)
      hydra.queue(request)
      hydra.run
      request.response
    end

    it_behaves_like 'instrumented request'
  end

  context 'with concurrent Hydra requests' do
    include_context 'integration context'

    let(:url_1) { "http://#{host}:#{@port}#{path}?status=200&simulate_timeout=true" }
    let(:url_2) { "http://#{host}:#{@port}#{path}" }
    let(:request_1) { Typhoeus::Request.new(url_1, timeout: 0.001) }
    let(:request_2) { Typhoeus::Request.new(url_2, method: :post, timeout: timeout, body: { status: 404 }) }

    subject(:request) do
      hydra = Typhoeus::Hydra.new
      hydra.queue(request_1)
      hydra.queue(request_2)
      hydra.run
    end

    it 'creates 3 spans' do
      expect { request }.to change { fetch_spans.count }.to 3
    end

    describe 'created spans' do
      let(:span_get) { spans.find { |span| span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_METHOD) == 'GET' } }
      let(:span_post) { spans.find { |span| span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_METHOD) == 'POST' } }
      let(:span_parent) { spans.find { |span| span.name == 'ethon.multi.request' } }

      before { request }

      it_behaves_like 'span' do
        let(:span) { span_get }
        let(:status) { nil }
      end

      it_behaves_like 'span' do
        let(:span) { span_post }
        let(:status) { '404' }
        let(:method) { 'POST' }
      end

      it 'has timeout set on GET request span' do
        expect(span_get).to have_error_message('Request has failed: Timeout was reached')
      end

      it 'has span hierarchy properly set up' do
        expect(span_get.parent_id).to eq(span_parent.span_id)
        expect(span_post.parent_id).to eq(span_parent.span_id)
      end
    end
  end
end
