require 'ddtrace/contrib/integration_examples'
require 'ddtrace/contrib/support/spec_helper'
require 'ddtrace/contrib/analytics_examples'

require 'ddtrace'
require 'net/http'
require 'time'
require 'json'
require_relative './test_http_server'

RSpec.describe 'net/http requests' do
  let(:host) { '127.0.0.1' }
  let(:port) { 5678 }
  let(:uri) { "http://#{host}:#{port}" }
  let(:server) { TestHTTPServer.new(host, port) }

  let(:client) { Net::HTTP.new(host, port) }
  let(:configuration_options) { {} }

  before do
    original_verbosity = $VERBOSE
    $VERBOSE = nil
    Net.send(:const_set, :HTTP, ::OriginalNetHTTP)
    $VERBOSE = original_verbosity
    server

    Datadog::Contrib::HTTP::Patcher.remove_instance_variable(:@done_once) if Datadog::Contrib::HTTP::Patcher.patched?
    Datadog.configure { |c| c.use :http, configuration_options }
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:http].reset_configuration!
    example.run
    Datadog.registry[:http].reset_configuration!
  end

  after do
    server.close
  end

  describe '#get' do
    subject(:response) { client.get(path) }

    let(:path) { '/my/path' }

    context 'that returns 200' do
      before { server.set_next_response(status: 200, body: '{}') }

      let(:content) { JSON.parse(response.body) }
      let(:span) { spans[1] }
      let(:connect_span) { spans[0] }

      it 'generates a well-formed trace' do
        expect(response.code).to eq('200')
        expect(content).to be_a_kind_of(Hash)
        expect(spans).to have(2).items
        expect(connect_span.name).to eq('http.connect')
        expect(connect_span.service).to eq('net/http')
        expect(span.name).to eq('http.request')
        expect(span.service).to eq('net/http')
        expect(span.resource).to eq('GET')
        expect(span.get_tag('http.url')).to eq(path)
        expect(span.get_tag('http.method')).to eq('GET')
        expect(span.get_tag('http.status_code')).to eq('200')
        expect(span.get_tag('out.host')).to eq(host)
        expect(span.get_tag('out.port')).to eq(port.to_s)
        expect(span.status).to eq(0)
      end

      it_behaves_like 'analytics for integration' do
        let(:analytics_enabled_var) { Datadog::Contrib::HTTP::Ext::ENV_ANALYTICS_ENABLED }
        let(:analytics_sample_rate_var) { Datadog::Contrib::HTTP::Ext::ENV_ANALYTICS_SAMPLE_RATE }
        before { response }
      end

      it_behaves_like 'measured span for integration', false do
        before { response }
      end

      it_behaves_like 'a peer service span'
    end

    context 'that returns 404' do
      before { server.set_next_response(status: 404, body: body) }

      let(:body) { '{ "code": 404, message": "Not found!" }' }
      let(:span) { spans[1] }
      let(:connect_span) { spans[0] }

      it 'generates a well-formed trace' do
        expect(response.code).to eq('404')
        expect(spans).to have(2).items
        expect(connect_span.name).to eq('http.connect')
        expect(connect_span.service).to eq('net/http')
        expect(span.name).to eq('http.request')
        expect(span.service).to eq('net/http')
        expect(span.resource).to eq('GET')
        expect(span.get_tag('http.url')).to eq(path)
        expect(span.get_tag('http.method')).to eq('GET')
        expect(span.get_tag('http.status_code')).to eq('404')
        expect(span.get_tag('out.host')).to eq(host)
        expect(span.get_tag('out.port')).to eq(port.to_s)
        expect(span.status).to eq(1)
        expect(span.get_tag('error.type')).to eq('Net::HTTPNotFound')
        expect(span.get_tag('error.msg')).to be nil
      end

      it_behaves_like 'a peer service span'

      context 'when configured with #after_request hook' do
        before { Datadog::Contrib::HTTP::Instrumentation.after_request(&callback) }

        after { Datadog::Contrib::HTTP::Instrumentation.instance_variable_set(:@after_request, nil) }

        context 'which defines each parameter' do
          let(:callback) do
            proc do |span, http, request, response|
              expect(span).to be_a_kind_of(Datadog::Span)
              expect(http).to be_a_kind_of(Net::HTTP)
              expect(request).to be_a_kind_of(Net::HTTP::Get)
              expect(response).to be_a_kind_of(Net::HTTPNotFound)
            end
          end

          it { expect(response.code).to eq('404') }
        end

        context 'which changes the error status' do
          let(:callback) do
            proc do |span, _http, _request, response|
              case response.code.to_i
              when 400...599
                if response.class.body_permitted? && !response.body.nil?
                  span.set_error([response.class, response.body[0...4095]])
                end
              end
            end
          end

          it 'generates a trace modified by the hook' do
            expect(response.code).to eq('404')
            expect(span.status).to eq(1)
            expect(span.get_tag('error.type')).to eq('Net::HTTPNotFound')
            expect(span.get_tag('error.msg')).to eq(body)
          end
        end
      end
    end
  end

  describe '#post' do
    subject(:response) { client.post(path, payload) }

    let(:path) { '/my/path' }
    let(:payload) { '{ "foo": "bar" }' }

    context 'that returns 201' do
      before { server.set_next_response(status: 201, body: '{}') }

      let(:span) { spans[1] }
      let(:connect_span) { spans[0] }

      it 'generates a well-formed trace' do
        expect(response.code).to eq('201')
        expect(spans).to have(2).items
        expect(connect_span.name).to eq('http.connect')
        expect(connect_span.service).to eq('net/http')

        expect(span.name).to eq('http.request')
        expect(span.service).to eq('net/http')
        expect(span.resource).to eq('POST')
        expect(span.get_tag('http.url')).to eq(path)
        expect(span.get_tag('http.method')).to eq('POST')
        expect(span.get_tag('http.status_code')).to eq('201')
        expect(span.get_tag('out.host')).to eq(host)
        expect(span.get_tag('out.port')).to eq(port.to_s)
        expect(span.status).to eq(0)
      end

      it_behaves_like 'a peer service span'
    end
  end

  describe '#start' do
    context 'which applies a pin to the Net::HTTP object' do
      before do
        server.set_next_response(status: 200, body: '{}')

        Net::HTTP.start(host, port) do |http|
          http.request(request)
        end
      end

      let(:request) { Net::HTTP::Get.new(path) }
      let(:path) { '/my/path' }
      let(:span) { spans[1] }
      let(:connect_span) { spans.first }

      it 'generates a well-formed trace' do
        expect(spans).to have(2).items
        expect(connect_span.name).to eq('http.connect')
        expect(connect_span.service).to eq('net/http')

        expect(span.name).to eq('http.request')
        expect(span.service).to eq('net/http')
        expect(span.resource).to eq('GET')
        expect(span.get_tag('http.url')).to eq(path)
        expect(span.get_tag('http.method')).to eq('GET')
        expect(span.get_tag('http.status_code')).to eq('200')
        expect(span.get_tag('out.host')).to eq(host)
        expect(span.get_tag('out.port')).to eq(port.to_s)
        expect(span.status).to eq(0)
      end

      it_behaves_like 'a peer service span'
    end
  end

  describe 'Net::HTTP object pin' do
    context 'when overriden with a different #service value' do
      subject(:response) { client.get(path) }

      before do
        server.set_next_response(status: 200, body: '{}')
        Datadog::Pin.get_from(client).service = service_name
      end

      let(:path) { '/my/path' }
      let(:service_name) { 'bar' }
      let(:span) { spans[1] }
      let(:connect_span) { spans[0] }

      it 'generates a well-formed trace' do
        expect(response.code).to eq('200')
        expect(spans).to have(2).items
        expect(connect_span.name).to eq('http.connect')
        expect(connect_span.service).to eq(service_name)
        expect(span.name).to eq('http.request')
        expect(span.service).to eq(service_name)
      end

      it_behaves_like 'a peer service span'
    end
  end

  context 'when split by domain' do
    subject(:response) { client.get(path) }

    let(:path) { '/my/path' }
    let(:connect_span) { spans[0] }
    let(:span) { spans[1] }
    let(:configuration_options) { super().merge(split_by_domain: true) }

    before { server.set_next_response(status: 200, body: '{}') }

    it do
      response
      expect(span.name).to eq(Datadog::Contrib::HTTP::Ext::SPAN_REQUEST)
      expect(span.service).to eq(host)
      expect(span.resource).to eq('GET')
    end

    context 'and the host matches a specific configuration' do
      before do
        Datadog.configure do |c|
          c.use :http, configuration_options
          c.use :http, describes: /127.0.0.1/ do |http|
            http.service_name = 'bar'
            http.split_by_domain = false
          end

          c.use :http, describes: /badexample\.com/ do |http|
            http.service_name = 'bar_bad'
            http.split_by_domain = false
          end
        end
      end

      it 'uses the configured service name over the domain name and the correct describes block' do
        response
        expect(span.service).to eq('bar')
      end
    end
  end

  describe 'distributed tracing' do
    let(:path) { '/my/path' }

    before do
      server.set_next_response(status: 200, body: '{}')
    end

    def expect_request_without_distributed_headers
      expect(server.requests[0][:method]).to eq 'GET'
      expect(server.requests[0][:path]).to eq path
      [
        Datadog::Ext::DistributedTracing::HTTP_HEADER_PARENT_ID,
        Datadog::Ext::DistributedTracing::HTTP_HEADER_TRACE_ID,
        Datadog::Ext::DistributedTracing::HTTP_HEADER_SAMPLING_PRIORITY
      ].each do |header|
        header_name = header.split('-').map(&:capitalize).join('-')
        expect(server.requests[0][:headers].keys).to_not include header_name
      end
    end

    context 'by default' do
      context 'and the tracer is enabled' do
        before do
          tracer.configure(enabled: true)
          tracer.trace('foo.bar') do |span|
            span.context.sampling_priority = sampling_priority
            client.get(path)
          end
        end

        let(:sampling_priority) { 10 }
        let(:distributed_tracing_headers) do
          {
            Datadog::Ext::DistributedTracing::HTTP_HEADER_PARENT_ID => span.span_id,
            Datadog::Ext::DistributedTracing::HTTP_HEADER_TRACE_ID => span.trace_id,
            Datadog::Ext::DistributedTracing::HTTP_HEADER_SAMPLING_PRIORITY => sampling_priority
          }
        end

        let(:span) { spans.last }

        it 'adds distributed tracing headers' do
          expect(server.requests[0][:method]).to eq 'GET'
          expect(server.requests[0][:path]).to eq path
          distributed_tracing_headers.all? do |(header, value)|
            header_name = header.split('-').map(&:capitalize).join('-')
            expect(server.requests[0][:headers][header_name]).to eq value.to_s
          end
        end
      end

      # This can happen if another http client uses net/http (e.g. restclient)
      # The goal here is to ensure we do not add multiple values for a given header
      context 'with existing distributed tracing headers' do
        before do
          tracer.configure(enabled: true)
          tracer.trace('foo.bar') do |span|
            span.context.sampling_priority = sampling_priority

            req = Net::HTTP::Get.new(path)
            req[Datadog::Ext::DistributedTracing::HTTP_HEADER_PARENT_ID] = 100
            req[Datadog::Ext::DistributedTracing::HTTP_HEADER_TRACE_ID] = 100
            req[Datadog::Ext::DistributedTracing::HTTP_HEADER_SAMPLING_PRIORITY] = 0

            Net::HTTP.start(host, port) do |http|
              http.request(req)
            end
          end
        end

        let(:sampling_priority) { 10 }
        let(:distributed_tracing_headers) do
          {
            Datadog::Ext::DistributedTracing::HTTP_HEADER_PARENT_ID => span.span_id,
            Datadog::Ext::DistributedTracing::HTTP_HEADER_TRACE_ID => span.trace_id,
            Datadog::Ext::DistributedTracing::HTTP_HEADER_SAMPLING_PRIORITY => sampling_priority
          }
        end

        let(:span) { spans.last }

        it 'adds distributed tracing headers' do
          expect(server.requests[0][:method]).to eq 'GET'
          expect(server.requests[0][:path]).to eq path
          distributed_tracing_headers.all? do |(header, value)|
            header_name = header.split('-').map(&:capitalize).join('-')
            expect(server.requests[0][:headers][header_name]).to eq value.to_s
          end
        end
      end

      context 'but the tracer is disabled' do
        before do
          tracer.configure(enabled: false)
          client.get(path)
        end

        it 'does not add distributed tracing headers' do
          expect(spans).to be_empty
          expect_request_without_distributed_headers
        end
      end
    end

    context 'when disabled' do
      before do
        Datadog.configure { |c| c.use :http, distributed_tracing: false }
        client.get(path)
      end

      after do
        Datadog.configure { |c| c.use :http, distributed_tracing: true }
      end

      let(:span) { spans.last }

      it 'does not add distributed tracing headers' do
        expect(span.name).to eq('http.request')
        expect_request_without_distributed_headers
      end
    end
  end

  describe 'connection exceptions' do
    # requests never raises exception by documentation of Net::HTTP
    subject(:response) { client.get(path) }

    let(:path) { '/my/path' }

    context 'that raises a timeout' do
      let(:timeout_error) { Net::OpenTimeout.new('execution expired') }
      let(:span) { spans.first }

      before { allow(TCPSocket).to receive(:open).and_raise(timeout_error) }

      it 'generates a well-formed trace with span tags available from request object' do
        expect { response }.to raise_error(timeout_error)
        expect(spans).to have(1).items
        expect(span.name).to eq('http.connect')
        expect(span.service).to eq('net/http')
        expect(span.resource).to eq("#{host}:#{port}")
        expect(span.get_tag('out.host')).to eq(host)
        expect(span.get_tag('out.port')).to eq(port.to_s)
        expect(span).to have_error
        expect(span).to have_error_type(timeout_error.class.to_s)
        expect(span).to have_error_message(timeout_error.message)
      end
    end

    context 'that raises an error' do
      let(:custom_error_message) { 'example error' }
      let(:custom_error) { StandardError.new(custom_error_message) }
      let(:span) { spans.first }
      let(:expected_error) { "Failed to open TCP connection to #{host}:#{port} (#{custom_error_message})" }

      before { allow(TCPSocket).to receive(:open).and_raise(custom_error) }

      it 'generates a well-formed trace with span tags available from request object' do
        expect { response }.to raise_error(StandardError, expected_error)
        expect(spans).to have(1).items
        expect(span.name).to eq('http.connect')
        expect(span.service).to eq('net/http')
        expect(span.resource).to eq("#{host}:#{port}")
        expect(span.get_tag('out.host')).to eq(host)
        expect(span.get_tag('out.port')).to eq(port.to_s)
        expect(span).to have_error
        expect(span).to have_error_type(custom_error.class.to_s)
        expect(span).to have_error_message(expected_error)
      end
    end

    context 'read timeout' do
      let(:span) { spans[1] }

      before do
        client.read_timeout = 1
        server.set_response_delay 1.25
      end

      it 'generates a well-formed trace with span tags available from request object' do
        expect { response }.to raise_error(Net::ReadTimeout)
        expect(spans).to have(2).items
        expect(span.name).to eq('http.request')
        expect(span.service).to eq('net/http')
        expect(span.resource).to eq('GET')
        expect(span.get_tag('http.url')).to eq(path)
        expect(span.get_tag('http.method')).to eq('GET')
        expect(span.get_tag('out.host')).to eq(host)
        expect(span.get_tag('out.port')).to eq(port.to_s)
        expect(span).to have_error
        expect(span).to have_error_type(Net::ReadTimeout.to_s)
        expect(span).to have_error_message('Net::ReadTimeout')
      end
    end
  end
end
