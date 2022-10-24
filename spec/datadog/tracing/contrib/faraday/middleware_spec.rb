# typed: ignore

require 'datadog/tracing/contrib/integration_examples'
require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/analytics_examples'

require 'faraday'

require 'datadog/tracing'
require 'datadog/tracing/distributed/headers/ext'
require 'datadog/tracing/metadata/ext'

RSpec.describe 'Faraday middleware' do
  let(:client) do
    ::Faraday.new('http://example.com') do |builder|
      builder.use(:ddtrace, middleware_options) if use_middleware
      builder.adapter(:test) do |stub|
        stub.get('/success') { |_| [200, {}, 'OK'] }
        stub.post('/failure') { |_| [500, {}, 'Boom!'] }
        stub.get('/not_found') { |_| [404, {}, 'Not Found.'] }
        stub.get('/error') { |_| raise ::Faraday::ConnectionFailed, 'Test error' }
      end
    end
  end

  let(:use_middleware) { true }
  let(:middleware_options) { {} }
  let(:configuration_options) { {} }

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
    subject(:response) { client.get('/success') }

    let(:use_middleware) { false }

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
    end

    it_behaves_like 'a peer service span' do
      let(:peer_hostname) { 'example.com' }
    end

    it 'executes without warnings' do
      expect { response }.to_not output(/WARNING/).to_stderr
    end

    context 'with default Faraday connection' do
      subject(:response) { client.get('http://example.com/success') }

      let(:client) { ::Faraday } # Use the singleton client

      before do
        # We mock HTTP requests we we can't configure
        # the test adapter for the default connection
        WebMock.enable!
        stub_request(:get, 'http://example.com/success').to_return(status: 200)
      end

      after { WebMock.disable! }

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
      end

      it 'executes without warnings' do
        expect { response }.to_not output(/WARNING/).to_stderr
      end
    end
  end

  context 'when there is no interference' do
    subject!(:response) { client.get('/success') }

    it do
      expect(response).to be_a_kind_of(::Faraday::Response)
      expect(response.body).to eq('OK')
      expect(response.status).to eq(200)
    end
  end

  context 'when there is successful request' do
    subject!(:response) { client.get('/success') }

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
    end

    it_behaves_like 'a peer service span' do
      let(:peer_hostname) { 'example.com' }
    end
  end

  context 'when there is a failing request' do
    subject!(:response) { client.post('/failure') }

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
    end

    it_behaves_like 'a peer service span' do
      let(:peer_hostname) { 'example.com' }
    end
  end

  context 'with library error' do
    subject(:response) { client.get('/error') }

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
    end

    it_behaves_like 'a peer service span' do
      let(:peer_hostname) { 'example.com' }

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
    subject!(:response) { client.get('/not_found') }

    it { expect(span).to_not have_error }
  end

  context 'when there is custom error handling' do
    subject!(:response) { client.get('not_found') }

    let(:middleware_options) { { error_handler: custom_handler } }
    let(:custom_handler) { ->(env) { (400...600).cover?(env[:status]) } }

    it { expect(span).to have_error }
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
      let(:peer_hostname) { 'example.com' }
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
        Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_TRACE_ID => span.trace_id.to_s,
        Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_PARENT_ID => span.span_id.to_s
      )
    end

    context 'but the tracer is disabled' do
      before { tracer.enabled = false }

      it do
        expect(headers).to_not include(Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_TRACE_ID)
        expect(headers).to_not include(Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_PARENT_ID)
        expect(spans.length).to eq(0)
      end
    end
  end

  context 'when distributed tracing is disabled' do
    subject(:response) { client.get('/success') }

    let(:middleware_options) { { distributed_tracing: false } }
    let(:headers) { response.env.request_headers }

    it do
      expect(headers).to_not include(Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_TRACE_ID)
      expect(headers).to_not include(Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_PARENT_ID)
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
      let(:peer_hostname) { 'example.com' }
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
      let(:peer_hostname) { 'example.com' }
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
