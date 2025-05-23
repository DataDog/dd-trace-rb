# typed: ignore

require 'roda'
require 'datadog'
require 'datadog/tracing/contrib/roda/instrumentation'
require 'datadog/tracing/contrib/roda/ext'
require 'datadog/tracing/contrib/analytics_examples'
require 'datadog/tracing/contrib/support/spec_helper'

RSpec.shared_examples_for 'shared examples for roda' do |test_method|
  let(:configuration_options) { {} }
  let(:test_class) do
    Class.new do
      prepend Datadog::Tracing::Contrib::Roda::Instrumentation
    end
  end
  let(:roda) { test_class.new }
  let(:instrumented_method) { roda.send(test_method) }

  before do
    Datadog.configure do |c|
      c.tracing.instrument :roda, configuration_options
    end
  end

  after do
    Datadog.registry[:roda].reset_configuration!
  end

  shared_context 'stubbed request' do
    let(:env) { {} }
    let(:response_method) { :get }
    let(:path) { '/' }

    let(:request) do
      instance_double(
        ::Rack::Request,
        env: env,
        request_method: response_method,
        path: path
      )
    end

    before do
      r = request
      test_class.send(:define_method, :request) do
        r
      end
    end
  end

  shared_context 'stubbed response' do
    let(:spy) { instance_double(Roda) }
    let(:response) { [response_code, instance_double(Hash), double('body')] }
    let(:response_code) { 200 }
    let(:response_headers) { double('body') }

    before do
      s = spy
      test_class.send(:define_method, test_method) do
        s.send(test_method)
      end
      expect(spy).to receive(test_method)
        .and_return(response)
    end
  end

  context 'when the response code is' do
    include_context 'stubbed request'
    include_context 'stubbed response'

    context '200' do
      let(:response_code) { 200 }

      it do
        instrumented_method
        expect(spans).to have(1).items
        expect(span.parent_id).to be 0
        expect(span.type).to eq(Datadog::Tracing::Metadata::Ext::HTTP::TYPE_INBOUND)
        expect(span.status).to eq(0)
        expect(span.name).to eq('roda.request')
        expect(span.resource).to eq('GET 200')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_METHOD)).to eq('GET')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_URL)).to eq('/')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE)).to eq(response_code.to_s)
      end
    end

    context '404' do
      let(:response_code) { 404 }
      let(:path) { '/unsuccessful_endpoint' }

      it do
        instrumented_method
        expect(spans).to have(1).items
        expect(span.parent_id).to be 0
        expect(span.type).to eq(Datadog::Tracing::Metadata::Ext::HTTP::TYPE_INBOUND)
        expect(span.resource).to eq('GET 404')
        expect(span.name).to eq('roda.request')
        expect(span.status).to eq(0)
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_METHOD)).to eq('GET')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_URL)).to eq('/unsuccessful_endpoint')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE)).to eq(response_code.to_s)
      end
    end

    context '500' do
      let(:response_code) { 500 }

      it do
        instrumented_method
        expect(spans).to have(1).items
        expect(span.parent_id).to be 0
        expect(span.type).to eq(Datadog::Tracing::Metadata::Ext::HTTP::TYPE_INBOUND)
        expect(span.resource).to eq('GET 500')
        expect(span.name).to eq('roda.request')
        expect(span.status).to eq(1)
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_METHOD)).to eq('GET')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_URL)).to eq('/')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE)).to eq(response_code.to_s)
      end
    end
  end

  context 'when the verb is' do
    include_context 'stubbed request'
    include_context 'stubbed response'

    context 'GET' do
      it do
        instrumented_method
        expect(spans).to have(1).items
        expect(span.parent_id).to be 0
        expect(span.type).to eq(Datadog::Tracing::Metadata::Ext::HTTP::TYPE_INBOUND)
        expect(span.status).to eq(0)
        expect(span.name).to eq('roda.request')
        expect(span.resource).to eq('GET 200')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_METHOD)).to eq('GET')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_URL)).to eq('/')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE)).to eq(response_code.to_s)
      end
    end

    context 'PUT' do
      let(:response_method) { :put }

      it do
        instrumented_method
        expect(spans).to have(1).items
        expect(span.parent_id).to be 0
        expect(span.type).to eq(Datadog::Tracing::Metadata::Ext::HTTP::TYPE_INBOUND)
        expect(span.status).to eq(0)
        expect(span.name).to eq('roda.request')
        expect(span.resource).to eq('PUT 200')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_METHOD)).to eq('PUT')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_URL)).to eq('/')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE)).to eq(response_code.to_s)
      end
    end
  end

  context 'when the path is' do
    include_context 'stubbed request'
    include_context 'stubbed response'

    context '/worlds' do
      let(:path) { 'worlds' }

      it do
        instrumented_method
        expect(spans).to have(1).items
        expect(span.parent_id).to be 0
        expect(span.type).to eq(Datadog::Tracing::Metadata::Ext::HTTP::TYPE_INBOUND)
        expect(span.status).to eq(0)
        expect(span.name).to eq('roda.request')
        expect(span.resource).to eq('GET 200')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_METHOD)).to eq('GET')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_URL)).to eq(path)
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE)).to eq(response_code.to_s)
      end
    end

    context '/worlds/:id' do
      let(:path) { 'worlds/1' }
      it do
        instrumented_method
        expect(spans).to have(1).items
        expect(span.parent_id).to be 0
        expect(span.type).to eq(Datadog::Tracing::Metadata::Ext::HTTP::TYPE_INBOUND)
        expect(span.status).to eq(0)
        expect(span.name).to eq('roda.request')
        expect(span.resource).to eq('GET 200')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_METHOD)).to eq('GET')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_URL)).to eq(path)
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE)).to eq(response_code.to_s)
      end
    end

    context 'articles?id=1' do
      let(:path) { 'articles?id=1' }
      it do
        instrumented_method
        expect(spans).to have(1).items
        expect(span.parent_id).to be 0
        expect(span.type).to eq(Datadog::Tracing::Metadata::Ext::HTTP::TYPE_INBOUND)
        expect(span.status).to eq(0)
        expect(span.name).to eq('roda.request')
        expect(span.resource).to eq('GET 200')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_METHOD)).to eq('GET')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_URL)).to eq(path)
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE)).to eq(response_code.to_s)
      end
    end
  end

  context 'when analytics' do
    include_context 'stubbed request'
    include_context 'stubbed response'
    it_behaves_like 'analytics for integration', ignore_global_flag: true do
      before { instrumented_method }
      let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Roda::Ext::ENV_ANALYTICS_ENABLED }
      let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Roda::Ext::ENV_ANALYTICS_SAMPLE_RATE }
    end
  end
end
