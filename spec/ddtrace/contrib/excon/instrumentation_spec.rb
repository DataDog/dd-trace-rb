require 'spec_helper'
require 'ddtrace/contrib/analytics_examples'

require 'excon'
require 'ddtrace'
require 'ddtrace/contrib/excon/middleware'

RSpec.describe Datadog::Contrib::Excon::Middleware do
  let(:tracer) { get_test_tracer }

  let(:connection_options) { { mock: true } }
  let(:middleware_options) { {} }
  let(:configuration_options) { { tracer: tracer } }

  let(:request_span) do
    tracer.writer.spans(:keep).find { |span| span.name == Datadog::Contrib::Excon::Ext::SPAN_REQUEST }
  end

  let(:all_request_spans) do
    tracer.writer.spans(:keep).find_all { |span| span.name == Datadog::Contrib::Excon::Ext::SPAN_REQUEST }
  end

  before(:each) do
    Datadog.configure do |c|
      c.use :excon, configuration_options
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:excon].reset_configuration!
    example.run
    Datadog.registry[:excon].reset_configuration!
    Excon.stubs.clear
  end

  let(:connection) do
    Excon.new('http://example.com', connection_options).tap do
      Excon.stub({ method: :get, path: '/success' }, body: 'OK', status: 200)
      Excon.stub({ method: :post, path: '/failure' }, body: 'Boom!', status: 500)
      Excon.stub({ method: :get, path: '/not_found' }, body: 'Not Found.', status: 404)
      Excon.stub(
        { method: :get, path: '/timeout' },
        lambda do |_request_params|
          raise Excon::Errors::Timeout, 'READ TIMEOUT'
        end
      )
    end
  end

  shared_context 'connection with custom middleware' do
    let(:connection_options) do
      super().merge(
        middlewares: [
          Excon::Middleware::ResponseParser,
          Datadog::Contrib::Excon::Middleware.with(middleware_options),
          Excon::Middleware::Mock
        ]
      )
    end
  end

  shared_context 'connection with default middleware' do
    let(:connection_options) do
      super().merge(middlewares: Datadog::Contrib::Excon::Middleware.with(middleware_options).around_default_stack)
    end
  end

  context 'when there is no interference' do
    subject!(:response) { connection.get(path: '/success') }

    it do
      expect(response).to be_a_kind_of(Excon::Response)
      expect(response.body).to eq('OK')
      expect(response.status).to eq(200)
    end
  end

  context 'when there is successful request' do
    subject!(:response) { connection.get(path: '/success') }

    it_behaves_like 'analytics for integration' do
      let(:analytics_enabled_var) { Datadog::Contrib::Excon::Ext::ENV_ANALYTICS_ENABLED }
      let(:analytics_sample_rate_var) { Datadog::Contrib::Excon::Ext::ENV_ANALYTICS_SAMPLE_RATE }
      let(:span) { request_span }
    end

    it do
      expect(request_span).to_not be nil
      expect(request_span.service).to eq(Datadog::Contrib::Excon::Ext::SERVICE_NAME)
      expect(request_span.name).to eq(Datadog::Contrib::Excon::Ext::SPAN_REQUEST)
      expect(request_span.resource).to eq('GET')
      expect(request_span.get_tag(Datadog::Ext::HTTP::METHOD)).to eq('GET')
      expect(request_span.get_tag(Datadog::Ext::HTTP::STATUS_CODE)).to eq(200)
      expect(request_span.get_tag(Datadog::Ext::HTTP::URL)).to eq('/success')
      expect(request_span.get_tag(Datadog::Ext::NET::TARGET_HOST)).to eq('example.com')
      expect(request_span.get_tag(Datadog::Ext::NET::TARGET_PORT)).to eq(80)
      expect(request_span.span_type).to eq(Datadog::Ext::HTTP::TYPE_OUTBOUND)
      expect(request_span).to_not have_error
    end
  end

  context 'when there is a failing request' do
    subject!(:response) { connection.post(path: '/failure') }

    it do
      expect(request_span.service).to eq(Datadog::Contrib::Excon::Ext::SERVICE_NAME)
      expect(request_span.name).to eq(Datadog::Contrib::Excon::Ext::SPAN_REQUEST)
      expect(request_span.resource).to eq('POST')
      expect(request_span.get_tag(Datadog::Ext::HTTP::METHOD)).to eq('POST')
      expect(request_span.get_tag(Datadog::Ext::HTTP::URL)).to eq('/failure')
      expect(request_span.get_tag(Datadog::Ext::HTTP::STATUS_CODE)).to eq(500)
      expect(request_span.get_tag(Datadog::Ext::NET::TARGET_HOST)).to eq('example.com')
      expect(request_span.get_tag(Datadog::Ext::NET::TARGET_PORT)).to eq(80)
      expect(request_span.span_type).to eq(Datadog::Ext::HTTP::TYPE_OUTBOUND)
      expect(request_span).to have_error
      expect(request_span).to have_error_type('Error 500')
      expect(request_span).to have_error_message('Boom!')
    end
  end

  context 'when the path is not found' do
    subject!(:response) { connection.get(path: '/not_found') }
    it { expect(request_span).to_not have_error }
  end

  context 'when the request times out' do
    subject(:response) { connection.get(path: '/timeout') }
    it do
      expect { subject }.to raise_error(Excon::Error::Timeout)
      expect(request_span.finished?).to eq(true)
      expect(request_span).to have_error
      expect(request_span.get_tag('error.type')).to eq('Excon::Error::Timeout')
    end

    context 'when the request is idempotent' do
      subject(:response) { connection.get(path: '/timeout', idempotent: true, retry_limit: 4) }
      it 'records separate spans' do
        expect { subject }.to raise_error(Excon::Error::Timeout)
        expect(all_request_spans.size).to eq(4)
        expect(all_request_spans.all?(&:finished?)).to eq(true)
      end
    end
  end

  context 'when there is custom error handling' do
    subject!(:response) { connection.get(path: 'not_found') }
    let(:configuration_options) { super().merge(error_handler: custom_handler) }
    let(:custom_handler) { ->(env) { (400...600).cover?(env[:status]) } }
    after(:each) { Datadog.configuration[:excon][:error_handler] = nil }
    it { expect(request_span).to have_error }
  end

  context 'when split by domain' do
    subject!(:response) { connection.get(path: '/success') }
    let(:configuration_options) { super().merge(split_by_domain: true) }
    after(:each) { Datadog.configuration[:excon][:split_by_domain] = false }

    it do
      expect(request_span.name).to eq(Datadog::Contrib::Excon::Ext::SPAN_REQUEST)
      expect(request_span.service).to eq('example.com')
      expect(request_span.resource).to eq('GET')
    end
  end

  context 'default request headers' do
    subject!(:response) do
      expect_any_instance_of(Datadog::Contrib::Excon::Middleware).to receive(:request_call)
        .and_wrap_original do |m, *args|
          m.call(*args).tap do |datum|
            # Assert request headers
            span = datum[:datadog_span]
            headers = datum[:headers]
            expect(headers).to include(Datadog::Ext::DistributedTracing::HTTP_HEADER_TRACE_ID => span.trace_id.to_s)
            expect(headers).to include(Datadog::Ext::DistributedTracing::HTTP_HEADER_PARENT_ID => span.span_id.to_s)
            expect(headers).to include(Datadog::Ext::DistributedTracing::HTTP_HEADER_SAMPLING_PRIORITY)
          end
        end

      connection.get(path: '/success')
    end

    it do
      expect(response).to be_a_kind_of(::Excon::Response)
      expect(response.body).to eq('OK')
      expect(response.status).to eq(200)
    end
  end

  context 'when distributed tracing is disabled' do
    let(:configuration_options) { super().merge(distributed_tracing: false) }
    after(:each) { Datadog.configuration[:excon][:distributed_tracing] = true }

    subject!(:response) do
      expect_any_instance_of(Datadog::Contrib::Excon::Middleware).to receive(:request_call)
        .and_wrap_original do |m, *args|
          m.call(*args).tap do |datum|
            # Assert request headers
            headers = datum[:headers]
            expect(headers).to_not include(Datadog::Ext::DistributedTracing::HTTP_HEADER_TRACE_ID)
            expect(headers).to_not include(Datadog::Ext::DistributedTracing::HTTP_HEADER_PARENT_ID)
            expect(headers).to_not include(Datadog::Ext::DistributedTracing::HTTP_HEADER_SAMPLING_PRIORITY)
          end
        end

      connection.get(path: '/success')
    end

    it do
      expect(response).to be_a_kind_of(::Excon::Response)
      expect(response.body).to eq('OK')
      expect(response.status).to eq(200)
    end

    context 'but the tracer is disabled' do
      subject!(:response) do
        # Disable the tracer
        tracer.enabled = false

        expect_any_instance_of(Datadog::Contrib::Excon::Middleware).to receive(:request_call)
          .and_wrap_original do |m, *args|
            m.call(*args).tap do |datum|
              # Assert request headers
              headers = datum[:headers]
              expect(headers).to_not include(Datadog::Ext::DistributedTracing::HTTP_HEADER_TRACE_ID)
              expect(headers).to_not include(Datadog::Ext::DistributedTracing::HTTP_HEADER_PARENT_ID)
              expect(headers).to_not include(Datadog::Ext::DistributedTracing::HTTP_HEADER_SAMPLING_PRIORITY)
            end
          end

        connection.get(path: '/success')
      end

      it do
        expect(response).to be_a_kind_of(::Excon::Response)
        expect(response.body).to eq('OK')
        expect(response.status).to eq(200)
      end
    end
  end

  context 'global service name' do
    let(:service_name) { 'excon-global' }

    before(:each) do
      @old_service_name = Datadog.configuration[:excon][:service_name]
      Datadog.configure { |c| c.use :excon, service_name: service_name }
    end

    after(:each) { Datadog.configure { |c| c.use :excon, service_name: @old_service_name } }

    it do
      Excon.stub({ method: :get, path: '/success' }, body: 'OK', status: 200)
      connection.get(path: '/success')
      expect(request_span.service).to eq(service_name)
    end
  end

  context 'service name per request' do
    subject!(:response) do
      Excon.stub({ method: :get, path: '/success' }, body: 'OK', status: 200)
      connection.get(path: '/success')
    end

    let(:middleware_options) { { service_name: service_name } }

    context 'with default middleware' do
      include_context 'connection with default middleware'
      let(:service_name) { 'request-with-default' }
      it { expect(request_span.service).to eq(service_name) }
    end

    context 'with custom middleware' do
      include_context 'connection with custom middleware'
      let(:service_name) { 'request-with-custom' }
      it { expect(request_span.service).to eq(service_name) }
    end
  end
end
