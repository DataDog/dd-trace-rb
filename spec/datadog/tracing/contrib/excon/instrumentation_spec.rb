require 'datadog/tracing/contrib/integration_examples'
require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/analytics_examples'
require 'datadog/tracing/contrib/environment_service_name_examples'

require 'excon'
require 'ddtrace'
require 'datadog/tracing/contrib/excon/middleware'

RSpec.describe Datadog::Tracing::Contrib::Excon::Middleware do
  let(:connection_options) { { mock: true } }
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
  let(:middleware_options) { {} }
  let(:configuration_options) { {} }

  let(:request_span) do
    spans.find { |span| span.name == Datadog::Tracing::Contrib::Excon::Ext::SPAN_REQUEST }
  end

  let(:all_request_spans) do
    spans.find_all { |span| span.name == Datadog::Tracing::Contrib::Excon::Ext::SPAN_REQUEST }
  end

  before do
    Datadog.configure do |c|
      c.tracing.instrument :excon, configuration_options
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:excon].reset_configuration!
    example.run
    Datadog.registry[:excon].reset_configuration!
    Excon.stubs.clear
  end

  shared_context 'connection with custom middleware' do
    let(:connection_options) do
      super().merge(
        middlewares: [
          Excon::Middleware::ResponseParser,
          described_class.with(middleware_options),
          Excon::Middleware::Mock
        ]
      )
    end
  end

  shared_context 'connection with default middleware' do
    let(:connection_options) do
      super().merge(middlewares: described_class.with(middleware_options).around_default_stack)
    end
  end

  context 'when there is no interference' do
    subject!(:response) { connection.get(path: '/success') }

    it do
      expect(response).to be_a_kind_of(Excon::Response)
      expect(response.body).to eq('OK')
      expect(response.status).to eq(200)
    end

    it_behaves_like 'environment service name', 'DD_TRACE_EXCON_SERVICE_NAME'
  end

  context 'when there is successful request' do
    subject!(:response) { connection.get(path: '/success') }

    it_behaves_like 'environment service name', 'DD_TRACE_EXCON_SERVICE_NAME'

    it_behaves_like 'analytics for integration' do
      let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Excon::Ext::ENV_ANALYTICS_ENABLED }
      let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Excon::Ext::ENV_ANALYTICS_SAMPLE_RATE }
      let(:span) { request_span }
    end

    it_behaves_like 'measured span for integration', false

    it do
      expect(request_span).to_not be nil
      expect(request_span.service).to eq(Datadog::Tracing::Contrib::Excon::Ext::DEFAULT_PEER_SERVICE_NAME)
      expect(request_span.name).to eq(Datadog::Tracing::Contrib::Excon::Ext::SPAN_REQUEST)
      expect(request_span.resource).to eq('GET')
      expect(request_span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_METHOD)).to eq('GET')
      expect(request_span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE)).to eq('200')
      expect(request_span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_URL)).to eq('/success')
      expect(request_span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_HOST)).to eq('example.com')
      expect(request_span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_PORT)).to eq(80)
      expect(request_span.span_type).to eq(Datadog::Tracing::Metadata::Ext::HTTP::TYPE_OUTBOUND)
      expect(request_span).to_not have_error

      expect(request_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('excon')
      expect(request_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('request')
      expect(request_span.get_tag('span.kind')).to eq('client')
    end

    it_behaves_like 'a peer service span' do
      let(:peer_hostname) { 'example.com' }
    end
  end

  context 'when there is a failing request' do
    subject!(:response) { connection.post(path: '/failure') }

    it_behaves_like 'environment service name', 'DD_TRACE_EXCON_SERVICE_NAME'

    it do
      expect(request_span.service).to eq(Datadog::Tracing::Contrib::Excon::Ext::DEFAULT_PEER_SERVICE_NAME)
      expect(request_span.name).to eq(Datadog::Tracing::Contrib::Excon::Ext::SPAN_REQUEST)
      expect(request_span.resource).to eq('POST')
      expect(request_span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_METHOD)).to eq('POST')
      expect(request_span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_URL)).to eq('/failure')
      expect(request_span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE)).to eq('500')
      expect(request_span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_HOST)).to eq('example.com')
      expect(request_span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_PORT)).to eq(80)
      expect(request_span.get_tag('span.kind')).to eq('client')
      expect(request_span.span_type).to eq(Datadog::Tracing::Metadata::Ext::HTTP::TYPE_OUTBOUND)
      expect(request_span).to have_error
      expect(request_span).to have_error_type('Error 500')
      expect(request_span).to have_error_message('Boom!')

      expect(request_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('excon')
      expect(request_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('request')
    end

    it_behaves_like 'a peer service span' do
      let(:peer_hostname) { 'example.com' }
    end
  end

  context 'when the path is not found' do
    subject!(:response) { connection.get(path: '/not_found') }

    it_behaves_like 'environment service name', 'DD_TRACE_EXCON_SERVICE_NAME'

    it { expect(request_span).to_not have_error }
  end

  context 'when the request times out' do
    subject(:response) { connection.get(path: '/timeout') }

    it_behaves_like 'environment service name', 'DD_TRACE_EXCON_SERVICE_NAME', error: Excon::Error::Timeout

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

    after { Datadog.configuration.tracing[:excon][:error_handler] = nil }

    it { expect(request_span).to have_error }
  end

  context 'when split by domain' do
    subject(:response) { connection.get(path: '/success') }

    let(:configuration_options) { super().merge(split_by_domain: true) }

    after { Datadog.configuration.tracing[:excon][:split_by_domain] = false }

    it do
      response
      expect(request_span.name).to eq(Datadog::Tracing::Contrib::Excon::Ext::SPAN_REQUEST)
      expect(request_span.service).to eq('example.com')
      expect(request_span.resource).to eq('GET')
    end

    it_behaves_like 'a peer service span' do
      let(:peer_hostname) { 'example.com' }
    end

    context 'and the host matches a specific configuration' do
      before do
        Datadog.configure do |c|
          c.tracing.instrument :excon, describes: /example\.com/ do |excon|
            excon.service_name = 'bar'
            excon.split_by_domain = false
          end

          c.tracing.instrument :excon, describes: /badexample\.com/ do |excon|
            excon.service_name = 'bar_bad'
            excon.split_by_domain = false
          end
        end
      end

      it 'uses the configured service name over the domain name and the correct describes block' do
        response
        expect(request_span.service).to eq('bar')
      end
    end
  end

  context 'default request headers' do
    subject!(:response) do
      expect_any_instance_of(described_class).to receive(:request_call)
        .and_wrap_original do |m, *args|
          m.call(*args).tap do |datum|
            # Assert request headers
            span = datum[:datadog_span]
            headers = datum[:headers]
            expect(headers).to include(
              'x-datadog-trace-id' => span.trace_id.to_s,
              'x-datadog-parent-id' => span.span_id.to_s
            )

            expect(headers).to include(
              'x-datadog-sampling-priority'
            )
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

    after { Datadog.configuration.tracing[:excon][:distributed_tracing] = true }

    subject!(:response) do
      expect_any_instance_of(described_class).to receive(:request_call)
        .and_wrap_original do |m, *args|
          m.call(*args).tap do |datum|
            # Assert request headers
            headers = datum[:headers]
            expect(headers).to_not include(
              'x-datadog-trace-id',
              'x-datadog-parent-id',
              'x-datadog-sampling-priority'
            )
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

        expect_any_instance_of(described_class).to receive(:request_call)
          .and_wrap_original do |m, *args|
            m.call(*args).tap do |datum|
              # Assert request headers
              headers = datum[:headers]
              expect(headers).to_not include('x-datadog-trace-id')
              expect(headers).to_not include('x-datadog-parent-id')
              expect(headers).to_not include('x-datadog-sampling-priority')
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
    subject(:get) { connection.get(path: '/success') }

    let(:service_name) { 'excon-global' }

    before do
      @old_service_name = Datadog.configuration.tracing[:excon][:service_name]
      Datadog.configure { |c| c.tracing.instrument :excon, service_name: service_name }
    end

    after { Datadog.configure { |c| c.tracing.instrument :excon, service_name: @old_service_name } }

    it do
      subject
      expect(request_span.service).to eq(service_name)
    end

    it_behaves_like 'a peer service span' do
      let(:span) { request_span }
      let(:peer_hostname) { 'example.com' }
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

      it_behaves_like 'a peer service span' do
        let(:span) { request_span }
        let(:peer_hostname) { 'example.com' }
      end
    end

    context 'with custom middleware' do
      include_context 'connection with custom middleware'
      let(:service_name) { 'request-with-custom' }

      it { expect(request_span.service).to eq(service_name) }

      it_behaves_like 'a peer service span' do
        let(:span) { request_span }
        let(:peer_hostname) { 'example.com' }
      end
    end
  end

  context 'when basic auth in url' do
    before do
      WebMock.enable!
      stub_request(:get, /example.com/).to_return(status: 200)
    end

    after { WebMock.disable! }

    it 'does not collect auth info' do
      Excon.get('http://username:password@example.com/sample/path')

      expect(span.get_tag('http.url')).to eq('/sample/path')
      expect(span.get_tag('out.host')).to eq('example.com')
    end
  end
end
