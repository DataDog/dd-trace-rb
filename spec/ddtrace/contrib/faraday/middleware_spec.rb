require 'ddtrace/contrib/integration_examples'
require 'ddtrace/contrib/support/spec_helper'
require 'ddtrace/contrib/analytics_examples'

require 'ddtrace'
require 'faraday'
require 'ddtrace/ext/distributed'

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

  let(:request_span) do
    spans.find { |span| span.name == Datadog::Contrib::Faraday::Ext::SPAN_REQUEST }
  end

  before(:each) do
    Datadog.configure do |c|
      c.use :faraday, configuration_options
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

      expect(request_span).to_not be nil
      expect(request_span.service).to eq(Datadog::Contrib::Faraday::Ext::SERVICE_NAME)
      expect(request_span.name).to eq(Datadog::Contrib::Faraday::Ext::SPAN_REQUEST)
      expect(request_span.resource).to eq('GET')
      expect(request_span.get_tag(Datadog::Ext::HTTP::METHOD)).to eq('GET')
      expect(request_span.get_tag(Datadog::Ext::HTTP::STATUS_CODE)).to eq('200')
      expect(request_span.get_tag(Datadog::Ext::HTTP::URL)).to eq('/success')
      expect(request_span.get_tag(Datadog::Ext::NET::TARGET_HOST)).to eq('example.com')
      expect(request_span.get_tag(Datadog::Ext::NET::TARGET_PORT)).to eq(80)
      expect(request_span.span_type).to eq(Datadog::Ext::HTTP::TYPE_OUTBOUND)
      expect(request_span).to_not have_error
    end

    it_behaves_like 'a peer service span'

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

        expect(request_span.service).to eq(Datadog::Contrib::Faraday::Ext::SERVICE_NAME)
        expect(request_span.name).to eq(Datadog::Contrib::Faraday::Ext::SPAN_REQUEST)
        expect(request_span.resource).to eq('GET')
        expect(request_span.get_tag(Datadog::Ext::HTTP::METHOD)).to eq('GET')
        expect(request_span.get_tag(Datadog::Ext::HTTP::STATUS_CODE)).to eq('200')
        expect(request_span.get_tag(Datadog::Ext::HTTP::URL)).to eq('/success')
        expect(request_span.get_tag(Datadog::Ext::NET::TARGET_HOST)).to eq('example.com')
        expect(request_span.get_tag(Datadog::Ext::NET::TARGET_PORT)).to eq(80)
        expect(request_span.span_type).to eq(Datadog::Ext::HTTP::TYPE_OUTBOUND)
        expect(request_span).to_not have_error
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
      let(:analytics_enabled_var) { Datadog::Contrib::Faraday::Ext::ENV_ANALYTICS_ENABLED }
      let(:analytics_sample_rate_var) { Datadog::Contrib::Faraday::Ext::ENV_ANALYTICS_SAMPLE_RATE }
      let(:span) { request_span }
    end

    it_behaves_like 'measured span for integration', false

    it do
      expect(request_span).to_not be nil
      expect(request_span.service).to eq(Datadog::Contrib::Faraday::Ext::SERVICE_NAME)
      expect(request_span.name).to eq(Datadog::Contrib::Faraday::Ext::SPAN_REQUEST)
      expect(request_span.resource).to eq('GET')
      expect(request_span.get_tag(Datadog::Ext::HTTP::METHOD)).to eq('GET')
      expect(request_span.get_tag(Datadog::Ext::HTTP::STATUS_CODE)).to eq('200')
      expect(request_span.get_tag(Datadog::Ext::HTTP::URL)).to eq('/success')
      expect(request_span.get_tag(Datadog::Ext::NET::TARGET_HOST)).to eq('example.com')
      expect(request_span.get_tag(Datadog::Ext::NET::TARGET_PORT)).to eq(80)
      expect(request_span.span_type).to eq(Datadog::Ext::HTTP::TYPE_OUTBOUND)
      expect(request_span).to_not have_error
    end

    it_behaves_like 'a peer service span'
  end

  context 'when there is a failing request' do
    subject!(:response) { client.post('/failure') }

    it do
      expect(request_span.service).to eq(Datadog::Contrib::Faraday::Ext::SERVICE_NAME)
      expect(request_span.name).to eq(Datadog::Contrib::Faraday::Ext::SPAN_REQUEST)
      expect(request_span.resource).to eq('POST')
      expect(request_span.get_tag(Datadog::Ext::HTTP::METHOD)).to eq('POST')
      expect(request_span.get_tag(Datadog::Ext::HTTP::URL)).to eq('/failure')
      expect(request_span.get_tag(Datadog::Ext::HTTP::STATUS_CODE)).to eq('500')
      expect(request_span.get_tag(Datadog::Ext::NET::TARGET_HOST)).to eq('example.com')
      expect(request_span.get_tag(Datadog::Ext::NET::TARGET_PORT)).to eq(80)
      expect(request_span.span_type).to eq(Datadog::Ext::HTTP::TYPE_OUTBOUND)
      expect(request_span).to have_error
      expect(request_span).to have_error_type('Error 500')
      expect(request_span).to have_error_message('Boom!')
    end

    it_behaves_like 'a peer service span'
  end

  context 'with library error' do
    subject(:response) { client.get('/error') }

    it do
      expect { response }.to raise_error(Faraday::ConnectionFailed)
      expect(request_span.service).to eq(Datadog::Contrib::Faraday::Ext::SERVICE_NAME)
      expect(request_span.name).to eq(Datadog::Contrib::Faraday::Ext::SPAN_REQUEST)
      expect(request_span.resource).to eq('GET')
      expect(request_span.get_tag(Datadog::Ext::HTTP::METHOD)).to eq('GET')
      expect(request_span.get_tag(Datadog::Ext::HTTP::URL)).to eq('/error')
      expect(request_span.get_tag(Datadog::Ext::HTTP::STATUS_CODE)).to be nil
      expect(request_span.get_tag(Datadog::Ext::NET::TARGET_HOST)).to eq('example.com')
      expect(request_span.get_tag(Datadog::Ext::NET::TARGET_PORT)).to eq(80)
      expect(request_span.span_type).to eq(Datadog::Ext::HTTP::TYPE_OUTBOUND)
      expect(request_span).to have_error
      expect(request_span).to have_error_type('Faraday::ConnectionFailed')
      expect(request_span).to have_error_message(/Test error/)
    end

    it_behaves_like 'a peer service span' do
      subject { client.get('/error') rescue nil }
    end
  end

  context 'when there is a client error' do
    subject!(:response) { client.get('/not_found') }

    it { expect(request_span).to_not have_error }
  end

  context 'when there is custom error handling' do
    subject!(:response) { client.get('not_found') }

    let(:middleware_options) { { error_handler: custom_handler } }
    let(:custom_handler) { ->(env) { (400...600).cover?(env[:status]) } }
    it { expect(request_span).to have_error }
  end

  context 'when split by domain' do
    subject(:response) { client.get('/success') }

    let(:configuration_options) { super().merge(split_by_domain: true) }

    it do
      response
      expect(request_span.name).to eq(Datadog::Contrib::Faraday::Ext::SPAN_REQUEST)
      expect(request_span.service).to eq('example.com')
      expect(request_span.resource).to eq('GET')
    end

    it_behaves_like 'a peer service span'

    context 'and the host matches a specific configuration' do
      before do
        Datadog.configure do |c|
          c.use :faraday, describes: /example\.com/ do |faraday|
            faraday.service_name = 'bar'
            faraday.split_by_domain = false
          end

          c.use :faraday, describes: /badexample\.com/ do |faraday|
            faraday.service_name = 'bar_bad'
            faraday.split_by_domain = false
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
    subject(:response) { client.get('/success') }

    let(:headers) { response.env.request_headers }

    it do
      expect(headers).to include(Datadog::Ext::DistributedTracing::HTTP_HEADER_TRACE_ID => request_span.trace_id.to_s)
      expect(headers).to include(Datadog::Ext::DistributedTracing::HTTP_HEADER_PARENT_ID => request_span.span_id.to_s)
    end

    context 'but the tracer is disabled' do
      before(:each) { tracer.enabled = false }
      it do
        expect(headers).to_not include(Datadog::Ext::DistributedTracing::HTTP_HEADER_TRACE_ID)
        expect(headers).to_not include(Datadog::Ext::DistributedTracing::HTTP_HEADER_PARENT_ID)
        expect(request_span).to be nil
      end
    end
  end

  context 'when distributed tracing is disabled' do
    subject(:response) { client.get('/success') }

    let(:middleware_options) { { distributed_tracing: false } }
    let(:headers) { response.env.request_headers }

    it do
      expect(headers).to_not include(Datadog::Ext::DistributedTracing::HTTP_HEADER_TRACE_ID)
      expect(headers).to_not include(Datadog::Ext::DistributedTracing::HTTP_HEADER_PARENT_ID)
    end
  end

  context 'global service name' do
    let(:service_name) { 'faraday-global' }

    before(:each) do
      @old_service_name = Datadog.configuration[:faraday][:service_name]
      Datadog.configure { |c| c.use :faraday, service_name: service_name }
    end

    after(:each) { Datadog.configure { |c| c.use :faraday, service_name: @old_service_name } }

    subject { client.get('/success') }

    it do
      subject
      expect(request_span.service).to eq(service_name)
    end

    it_behaves_like 'a peer service span' do
      let(:span) { request_span }
    end
  end

  context 'service name per request' do
    subject!(:response) { client.get('/success') }

    let(:middleware_options) { { service_name: service_name } }
    let(:service_name) { 'adhoc-request' }

    it do
      expect(request_span.service).to eq(service_name)
    end

    it_behaves_like 'a peer service span' do
      let(:span) { request_span }
    end
  end

  context 'configuration override' do
    subject(:response) { client.get('/success') }

    context 'with global configuration' do
      let(:configuration_options) { super().merge(service_name: 'global') }

      it 'uses the global value' do
        subject
        expect(request_span.service).to eq('global')
      end

      context 'and per-host configuration' do
        before do
          Datadog.configure do |c|
            c.use :faraday, describes: /example\.com/, service_name: 'host'
          end
        end

        it 'uses per-host override' do
          subject
          expect(request_span.service).to eq('host')
        end

        context 'with middleware instance configuration' do
          let(:middleware_options) { super().merge(service_name: 'instance') }

          it 'uses middleware instance override' do
            subject
            expect(request_span.service).to eq('instance')
          end
        end
      end
    end
  end
end
