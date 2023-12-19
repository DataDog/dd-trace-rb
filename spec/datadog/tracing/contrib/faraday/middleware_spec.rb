require 'datadog/tracing/contrib/integration_examples'
require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/analytics_examples'
require 'datadog/tracing/contrib/environment_service_name_examples'
require 'datadog/tracing/contrib/span_attribute_schema_examples'
require 'datadog/tracing/contrib/peer_service_configuration_examples'
require 'datadog/tracing/contrib/support/http'

require 'faraday'

require 'datadog/tracing'
require 'datadog/tracing/metadata/ext'

RSpec.describe 'Faraday middleware' do
  let(:client) do
    ::Faraday.new('http://example.com') do |builder|
      builder.use(:ddtrace, middleware_options) if use_middleware
      builder.adapter(:test) do |stub|
        stub.get('/success') { |_| [200, response_headers, 'OK'] }
        stub.post('/failure') { |_| [500, {}, 'Boom!'] }
        stub.get('/not_found') { |_| [404, {}, 'Not Found.'] }
        stub.get('/error') { |_| raise ::Faraday::ConnectionFailed, 'Test error' }
      end
    end
  end

  let(:use_middleware) { true }
  let(:middleware_options) { {} }
  let(:configuration_options) { {} }
  let(:response_headers) { {} }

  before do
    Datadog.configure do |c|
      c.tracing.instrument :faraday, configuration_options
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:faraday].reset_configuration!
    example.run
    Datadog.registry[:faraday].reset_configuration!
  end

  context 'without explicit middleware configured' do
    subject(:response) { client.get('/success', nil, request_headers) }
    let(:request_headers) { {} }

    let(:use_middleware) { false }

    it_behaves_like 'environment service name', 'DD_TRACE_FARADAY_SERVICE_NAME'
    it_behaves_like 'configured peer service span', 'DD_TRACE_FARADAY_PEER_SERVICE'
    it_behaves_like 'schema version span'

    it 'uses default configuration' do
      expect(response.status).to eq(200)

      expect(span).to_not be nil
      expect(span.service).to eq(Datadog::Tracing::Contrib::Faraday::Ext::DEFAULT_PEER_SERVICE_NAME)
      expect(span.name).to eq(Datadog::Tracing::Contrib::Faraday::Ext::SPAN_REQUEST)
      expect(span.resource).to eq('GET')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_METHOD)).to eq('GET')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE)).to eq('200')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_URL)).to eq('/success')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_HOST)).to eq('example.com')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_PORT)).to eq(80)
      expect(span.span_type).to eq(Datadog::Tracing::Metadata::Ext::HTTP::TYPE_OUTBOUND)
      expect(span).to_not have_error

      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('faraday')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('request')
      expect(span.get_tag('span.kind')).to eq('client')
    end

    it_behaves_like 'a peer service span' do
      let(:peer_service_val) { 'example.com' }
      let(:peer_service_source) { 'peer.hostname' }
    end

    it 'executes without warnings' do
      expect { response }.to_not output(/WARNING/).to_stderr
    end

    context 'when configured with global tag headers' do
      before { response }

      let(:request_headers) { { 'Request-Id' => 'test-request' } }
      let(:response_headers) { { 'Response-Id' => 'test-response' } }

      include_examples 'with request tracer header tags' do
        let(:request_header_tag) { 'request-id' }
        let(:request_header_tag_value) { 'test-request' }
      end

      include_examples 'with response tracer header tags' do
        let(:response_header_tag) { 'response-id' }
        let(:response_header_tag_value) { 'test-response' }
      end
    end

    context 'with default Faraday connection' do
      subject(:response) { client.get('http://example.com/success') }

      let(:client) { ::Faraday } # Use the singleton client

      before do
        # We mock HTTP requests we we can't configure
        # the test adapter for the default connection
        WebMock.enable!(allow: agent_url)
        stub_request(:get, /example.com/).to_return(status: 200)
      end

      after { WebMock.disable! }

      it_behaves_like 'environment service name', 'DD_TRACE_FARADAY_SERVICE_NAME'
      it_behaves_like 'configured peer service span', 'DD_TRACE_FARADAY_PEER_SERVICE'
      it_behaves_like 'schema version span'

      it 'uses default configuration' do
        expect(response.status).to eq(200)

        expect(span.service).to eq(Datadog::Tracing::Contrib::Faraday::Ext::DEFAULT_PEER_SERVICE_NAME)
        expect(span.name).to eq(Datadog::Tracing::Contrib::Faraday::Ext::SPAN_REQUEST)
        expect(span.resource).to eq('GET')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_METHOD)).to eq('GET')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE)).to eq('200')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_URL)).to eq('/success')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_HOST)).to eq('example.com')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_PORT)).to eq(80)
        expect(span.span_type).to eq(Datadog::Tracing::Metadata::Ext::HTTP::TYPE_OUTBOUND)
        expect(span).to_not have_error

        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('faraday')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('request')
        expect(span.get_tag('span.kind')).to eq('client')
      end

      it 'executes without warnings' do
        expect { response }.to_not output(/WARNING/).to_stderr
      end

      context 'with basic auth' do
        subject(:response) { client.get('http://username:password@example.com/success') }

        it 'does not collect auth info' do
          expect(response.status).to eq(200)

          expect(span.get_tag('http.url')).to eq('/success')
        end

        it 'executes without warnings' do
          expect { response }.to_not output(/WARNING/).to_stderr
        end
      end

      context 'with query sting in url' do
        subject(:response) { client.get('http://example.com/success?foo=bar') }

        it 'does not collect query string' do
          expect(response.status).to eq(200)

          expect(span.get_tag('http.url')).to eq('/success')
        end

        it 'executes without warnings' do
          expect { response }.to_not output(/WARNING/).to_stderr
        end
      end
    end
  end

  context 'when there is no interference' do
    subject!(:response) { client.get('/success') }

    it_behaves_like 'environment service name', 'DD_TRACE_FARADAY_SERVICE_NAME'
    it_behaves_like 'configured peer service span', 'DD_TRACE_FARADAY_PEER_SERVICE'
    it_behaves_like 'schema version span'

    it do
      expect(response).to be_a_kind_of(::Faraday::Response)
      expect(response.body).to eq('OK')
      expect(response.status).to eq(200)
    end
  end

  context 'when there is successful request' do
    subject!(:response) { client.get('/success') }

    it_behaves_like 'environment service name', 'DD_TRACE_FARADAY_SERVICE_NAME'
    it_behaves_like 'configured peer service span', 'DD_TRACE_FARADAY_PEER_SERVICE'
    it_behaves_like 'schema version span'

    it_behaves_like 'analytics for integration' do
      let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Faraday::Ext::ENV_ANALYTICS_ENABLED }
      let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Faraday::Ext::ENV_ANALYTICS_SAMPLE_RATE }
    end

    it_behaves_like 'measured span for integration', false

    it do
      expect(span).to_not be nil
      expect(span.service).to eq(Datadog::Tracing::Contrib::Faraday::Ext::DEFAULT_PEER_SERVICE_NAME)
      expect(span.name).to eq(Datadog::Tracing::Contrib::Faraday::Ext::SPAN_REQUEST)
      expect(span.resource).to eq('GET')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_METHOD)).to eq('GET')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE)).to eq('200')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_URL)).to eq('/success')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_HOST)).to eq('example.com')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_PORT)).to eq(80)
      expect(span.span_type).to eq(Datadog::Tracing::Metadata::Ext::HTTP::TYPE_OUTBOUND)
      expect(span).to_not have_error

      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('faraday')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('request')
      expect(span.get_tag('span.kind')).to eq('client')
    end

    it_behaves_like 'a peer service span' do
      let(:peer_service_val) { 'example.com' }
      let(:peer_service_source) { 'peer.hostname' }
    end
  end

  context 'when there is a failing request' do
    subject!(:response) { client.post('/failure') }

    it_behaves_like 'environment service name', 'DD_TRACE_FARADAY_SERVICE_NAME'
    it_behaves_like 'configured peer service span', 'DD_TRACE_FARADAY_PEER_SERVICE'
    it_behaves_like 'schema version span'

    it do
      expect(span.service).to eq(Datadog::Tracing::Contrib::Faraday::Ext::DEFAULT_PEER_SERVICE_NAME)
      expect(span.name).to eq(Datadog::Tracing::Contrib::Faraday::Ext::SPAN_REQUEST)
      expect(span.resource).to eq('POST')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_METHOD)).to eq('POST')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_URL)).to eq('/failure')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE)).to eq('500')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_HOST)).to eq('example.com')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_PORT)).to eq(80)
      expect(span.span_type).to eq(Datadog::Tracing::Metadata::Ext::HTTP::TYPE_OUTBOUND)
      expect(span).to have_error
      expect(span).to have_error_type('Error 500')
      expect(span).to have_error_message('Boom!')

      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('faraday')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('request')
      expect(span.get_tag('span.kind')).to eq('client')
    end

    it_behaves_like 'a peer service span' do
      let(:peer_service_val) { 'example.com' }
      let(:peer_service_source) { 'peer.hostname' }
    end
  end

  context 'with library error' do
    subject(:response) { client.get('/error') }

    it_behaves_like 'environment service name', 'DD_TRACE_FARADAY_SERVICE_NAME', error: Faraday::ConnectionFailed
    it_behaves_like 'configured peer service span', 'DD_TRACE_FARADAY_PEER_SERVICE', error: Faraday::ConnectionFailed

    it do
      expect { response }.to raise_error(Faraday::ConnectionFailed)
      expect(span.service).to eq(Datadog::Tracing::Contrib::Faraday::Ext::DEFAULT_PEER_SERVICE_NAME)
      expect(span.name).to eq(Datadog::Tracing::Contrib::Faraday::Ext::SPAN_REQUEST)
      expect(span.resource).to eq('GET')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_METHOD)).to eq('GET')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_URL)).to eq('/error')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE)).to be nil
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_HOST)).to eq('example.com')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_PORT)).to eq(80)
      expect(span.span_type).to eq(Datadog::Tracing::Metadata::Ext::HTTP::TYPE_OUTBOUND)
      expect(span).to have_error
      expect(span).to have_error_type('Faraday::ConnectionFailed')
      expect(span).to have_error_message(/Test error/)

      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('faraday')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('request')
      expect(span.get_tag('span.kind')).to eq('client')
    end

    context 'when given `on_error`' do
      let(:configuration_options) { { on_error: proc { @error_handler_called = true } } }

      it do
        expect { response }.to raise_error(Faraday::ConnectionFailed)

        expect(span).not_to have_error
        expect(@error_handler_called).to be_truthy
      end
    end

    it_behaves_like 'a peer service span' do
      let(:peer_service_val) { 'example.com' }
      let(:peer_service_source) { 'peer.hostname' }

      subject do
        begin
          client.get('/error')
        rescue Faraday::ConnectionFailed
          nil
        end
      end
    end
  end

  context 'when there is a client error' do
    it do
      client.get('/not_found')

      expect(span).to have_error
    end

    context 'when given from configuration options' do
      let(:configuration_options) { { error_status_codes: 500...600 } }

      it do
        client.get('not_found')

        expect(span).not_to have_error
      end
    end
  end

  context 'when split by domain' do
    subject(:response) { client.get('/success') }

    let(:configuration_options) { super().merge(split_by_domain: true) }

    it do
      response
      expect(span.name).to eq(Datadog::Tracing::Contrib::Faraday::Ext::SPAN_REQUEST)
      expect(span.service).to eq('example.com')
      expect(span.resource).to eq('GET')
    end

    it_behaves_like 'a peer service span' do
      let(:peer_service_val) { 'example.com' }
      let(:peer_service_source) { 'peer.hostname' }
    end

    context 'and the host matches a specific configuration' do
      before do
        Datadog.configure do |c|
          c.tracing.instrument :faraday, describes: /example\.com/ do |faraday|
            faraday.service_name = 'bar'
            faraday.split_by_domain = false
          end

          c.tracing.instrument :faraday, describes: /badexample\.com/ do |faraday|
            faraday.service_name = 'bar_bad'
            faraday.split_by_domain = false
          end
        end
      end

      it 'uses the configured service name over the domain name and the correct describes block' do
        response
        expect(span.service).to eq('bar')
      end
    end
  end

  context 'default request headers' do
    subject(:response) { client.get('/success') }

    let(:headers) { response.env.request_headers }

    it do
      expect(headers).to include(
        'x-datadog-trace-id' => low_order_trace_id(span.trace_id).to_s,
        'x-datadog-parent-id' => span.span_id.to_s
      )
    end

    context 'but the tracer is disabled' do
      before { tracer.enabled = false }

      it do
        expect(headers).to_not include('x-datadog-trace-id')
        expect(headers).to_not include('x-datadog-parent-id')
        expect(spans.length).to eq(0)
      end
    end
  end

  context 'when distributed tracing is disabled' do
    subject(:response) { client.get('/success') }

    let(:middleware_options) { { distributed_tracing: false } }
    let(:headers) { response.env.request_headers }

    it do
      expect(headers).to_not include('x-datadog-trace-id')
      expect(headers).to_not include('x-datadog-parent-id')
    end
  end

  context 'global service name' do
    let(:service_name) { 'faraday-global' }

    before do
      @old_service_name = Datadog.configuration.tracing[:faraday][:service_name]
      Datadog.configure { |c| c.tracing.instrument :faraday, service_name: service_name }
    end

    after { Datadog.configure { |c| c.tracing.instrument :faraday, service_name: @old_service_name } }

    subject { client.get('/success') }

    it do
      subject
      expect(span.service).to eq(service_name)
    end

    it_behaves_like 'a peer service span' do
      let(:peer_service_val) { 'example.com' }
      let(:peer_service_source) { 'peer.hostname' }
    end
  end

  context 'service name per request' do
    subject!(:response) { client.get('/success') }

    let(:middleware_options) { { service_name: service_name } }
    let(:service_name) { 'adhoc-request' }

    it do
      expect(span.service).to eq(service_name)
    end

    it_behaves_like 'a peer service span' do
      let(:peer_service_val) { 'example.com' }
      let(:peer_service_source) { 'peer.hostname' }
    end
  end

  context 'configuration override' do
    subject(:response) { client.get('/success') }

    context 'with global configuration' do
      let(:configuration_options) { super().merge(service_name: 'global') }

      it 'uses the global value' do
        subject
        expect(span.service).to eq('global')
      end

      context 'and per-host configuration' do
        before do
          Datadog.configure do |c|
            c.tracing.instrument :faraday, describes: /example\.com/, service_name: 'host'
          end
        end

        it 'uses per-host override' do
          subject
          expect(span.service).to eq('host')
        end

        context 'with middleware instance configuration' do
          let(:middleware_options) { super().merge(service_name: 'instance') }

          it 'uses middleware instance override' do
            subject
            expect(span.service).to eq('instance')
          end
        end
      end
    end
  end
end
