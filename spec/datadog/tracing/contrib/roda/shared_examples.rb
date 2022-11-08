require 'roda'
require 'ddtrace'
require 'datadog/tracing/contrib/roda/instrumentation'
require 'datadog/tracing/contrib/roda/ext'
require 'datadog/tracing/contrib/analytics_examples'
require 'datadog/tracing/contrib/support/spec_helper'

RSpec.shared_examples_for 'shared examples for roda' do |test_method|
  let(:configuration_options) { { tracer: tracer } }
  let(:tracer) { tracer }
  let(:spans) { tracer.writer.spans }
  let(:span) { spans.first }
  let(:roda) { test_class.new }
  let(:test_class) do
    Class.new do
      prepend Datadog::Tracing::Contrib::Roda::Instrumentation
    end
  end
  let(:instrumented_method) { roda.send(test_method) }

  before(:each) do
    Datadog.configure do |c|
      c.use :roda, configuration_options
    end
  end

  after(:each) do
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
        expect(span.parent).to be nil
        expect(span.span_type).to eq(Datadog::Ext::HTTP::TYPE_INBOUND)
        expect(span.status).to eq(0)
        expect(span.name).to eq('roda.request')
        expect(span.resource).to eq('GET')
        expect(span.get_tag(Datadog::Ext::HTTP::METHOD)).to eq('GET')
        expect(span.get_tag(Datadog::Ext::HTTP::URL)).to eq('/')
        expect(span.get_tag(Datadog::Ext::HTTP::STATUS_CODE)).to eq(response_code.to_s)
      end
    end

    context '404' do
      let(:response_code) { 404 }
      let(:path) { '/unsuccessful_endpoint' }

      it do
        instrumented_method
        expect(spans).to have(1).items
        expect(span.parent).to be nil
        expect(span.span_type).to eq(Datadog::Ext::HTTP::TYPE_INBOUND)
        expect(span.resource).to eq('GET')
        expect(span.name).to eq('roda.request')
        expect(span.status).to eq(0)
        expect(span.get_tag(Datadog::Ext::HTTP::METHOD)).to eq('GET')
        expect(span.get_tag(Datadog::Ext::HTTP::URL)).to eq('/unsuccessful_endpoint')
        expect(span.get_tag(Datadog::Ext::HTTP::STATUS_CODE)).to eq(response_code.to_s)
     end
    end

    context '500' do
      let(:response_code) { 500 }

      it do
        instrumented_method
        expect(spans).to have(1).items
        expect(span.parent).to be nil
        expect(span.span_type).to eq(Datadog::Ext::HTTP::TYPE_INBOUND)
        expect(span.resource).to eq('GET')
        expect(span.name).to eq('roda.request')
        expect(span.status).to eq(1)
        expect(span.get_tag(Datadog::Ext::HTTP::METHOD)).to eq('GET')
        expect(span.get_tag(Datadog::Ext::HTTP::URL)).to eq('/')
        expect(span.get_tag(Datadog::Ext::HTTP::STATUS_CODE)).to eq(response_code.to_s)
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
        expect(span.parent).to be nil
        expect(span.span_type).to eq(Datadog::Ext::HTTP::TYPE_INBOUND)
        expect(span.status).to eq(0)
        expect(span.name).to eq('roda.request')
        expect(span.resource).to eq('GET')
        expect(span.get_tag(Datadog::Ext::HTTP::METHOD)).to eq('GET')
        expect(span.get_tag(Datadog::Ext::HTTP::URL)).to eq('/')
        expect(span.get_tag(Datadog::Ext::HTTP::STATUS_CODE)).to eq(response_code.to_s)
      end
    end

    context 'PUT' do
      let(:response_method) { :put }

      it do
        instrumented_method
        expect(spans).to have(1).items
        expect(span.parent).to be nil
        expect(span.span_type).to eq(Datadog::Ext::HTTP::TYPE_INBOUND)
        expect(span.status).to eq(0)
        expect(span.name).to eq('roda.request')
        expect(span.resource).to eq('PUT')
        expect(span.get_tag(Datadog::Ext::HTTP::METHOD)).to eq('PUT')
        expect(span.get_tag(Datadog::Ext::HTTP::URL)).to eq('/')
        expect(span.get_tag(Datadog::Ext::HTTP::STATUS_CODE)).to eq(response_code.to_s)
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
        expect(span.parent).to be nil
        expect(span.span_type).to eq(Datadog::Ext::HTTP::TYPE_INBOUND)
        expect(span.status).to eq(0)
        expect(span.name).to eq('roda.request')
        expect(span.resource).to eq('GET')
        expect(span.get_tag(Datadog::Ext::HTTP::METHOD)).to eq('GET')
        expect(span.get_tag(Datadog::Ext::HTTP::URL)).to eq(path)
        expect(span.get_tag(Datadog::Ext::HTTP::STATUS_CODE)).to eq(response_code.to_s)
      end
    end

    context '/worlds/:id' do
      let(:path) { 'worlds/1' }
      it do
        instrumented_method
        expect(spans).to have(1).items
        expect(span.parent).to be nil
        expect(span.span_type).to eq(Datadog::Ext::HTTP::TYPE_INBOUND)
        expect(span.status).to eq(0)
        expect(span.name).to eq('roda.request')
        expect(span.resource).to eq('GET')
        expect(span.get_tag(Datadog::Ext::HTTP::METHOD)).to eq('GET')
        expect(span.get_tag(Datadog::Ext::HTTP::URL)).to eq(path)
        expect(span.get_tag(Datadog::Ext::HTTP::STATUS_CODE)).to eq(response_code.to_s)
      end
    end

    context 'articles?id=1' do
      let(:path) { 'articles?id=1' }
      it do
        instrumented_method
        expect(spans).to have(1).items
        expect(span.parent).to be nil
        expect(span.span_type).to eq(Datadog::Ext::HTTP::TYPE_INBOUND)
        expect(span.status).to eq(0)
        expect(span.name).to eq('roda.request')
        expect(span.resource).to eq('GET')
        expect(span.get_tag(Datadog::Ext::HTTP::METHOD)).to eq('GET')
        expect(span.get_tag(Datadog::Ext::HTTP::URL)).to eq(path)
        expect(span.get_tag(Datadog::Ext::HTTP::STATUS_CODE)).to eq(response_code.to_s)
      end
    end
  end

  context 'when distributed tracing' do
    include_context 'stubbed request'

    let(:sampling_priority) { Datadog::Ext::Priority::USER_KEEP.to_s }

    context 'is enabled' do
      context 'without origin' do
        include_context 'stubbed response' do
          let(:env) do
            {
              'HTTP_X_DATADOG_TRACE_ID' => '40000',
              'HTTP_X_DATADOG_PARENT_ID' => '50000',
              'HTTP_X_DATADOG_SAMPLING_PRIORITY' => sampling_priority
            }
          end
        end

        it do
          instrumented_method
          expect(Datadog.configuration[:roda][:distributed_tracing]).to be(true)
          expect(spans).to have(1).items
          expect(span.trace_id).to eq(40000)
          expect(span.parent_id).to eq(50000)
          expect(span.get_metric(Datadog::Ext::DistributedTracing::SAMPLING_PRIORITY_KEY)).to eq(sampling_priority.to_f)
          expect(span.get_tag(Datadog::Ext::DistributedTracing::ORIGIN_KEY)).to be nil
        end
      end

      context 'with origin' do
        include_context 'stubbed response' do
          let(:env) do
            {
              'HTTP_X_DATADOG_TRACE_ID' => '10000',
              'HTTP_X_DATADOG_PARENT_ID' => '20000',
              'HTTP_X_DATADOG_SAMPLING_PRIORITY' => sampling_priority,
              'HTTP_X_DATADOG_ORIGIN' => 'synthetics'
            }
          end
        end

        it do
          instrumented_method
          expect(Datadog.configuration[:roda][:distributed_tracing]).to be(true)
          expect(spans).to have(1).items
          expect(span.trace_id).to eq(10000)
          expect(span.parent_id).to eq(20000)
          expect(span.get_metric(Datadog::Ext::DistributedTracing::SAMPLING_PRIORITY_KEY)).to eq(sampling_priority.to_f)
          expect(span.get_tag(Datadog::Ext::DistributedTracing::ORIGIN_KEY)).to eq('synthetics')
        end
      end
    end

    context 'is disabled' do
      let(:configuration_options) { { tracer: tracer, distributed_tracing: false } }
      include_context 'stubbed response' do
        let(:env) do
          {
            'HTTP_X_DATADOG_TRACE_ID' => '40000',
            'HTTP_X_DATADOG_PARENT_ID' => '50000',
            'HTTP_X_DATADOG_SAMPLING_PRIORITY' => sampling_priority
          }
        end
      end

      it 'does not take on the passed in trace context' do
        instrumented_method
        expect(Datadog.configuration[:roda][:distributed_tracing]).to be(false)
        expect(spans).to have(1).items
        expect(span.trace_id).to_not eq(40000)
        expect(span.parent_id).to_not eq(50000)
      end
    end
  end

  context 'when analytics' do
    include_context 'stubbed request'
    include_context 'stubbed response'
    it_behaves_like 'analytics for integration', ignore_global_flag: false do
      before { instrumented_method }
      let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Roda::Ext::ENV_ANALYTICS_ENABLED }
      let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Roda::Ext::ENV_ANALYTICS_SAMPLE_RATE }
    end
  end
end
