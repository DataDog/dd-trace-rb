require 'datadog/tracing/contrib/integration_examples'
require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/analytics_examples'
require 'datadog/tracing/contrib/environment_service_name_examples'
require 'datadog/tracing/contrib/http_examples'

require 'ddtrace'
require 'net/http'
require 'time'
require 'json'

RSpec.describe 'net/http requests' do
  before { WebMock.enable! }

  after do
    WebMock.reset!
    WebMock.disable!
  end

  let(:host) { '127.0.0.1' }
  let(:port) { 1234 }
  let(:uri) { "http://#{host}:#{port}" }
  let(:path) { '/my/path' }

  let(:client) { Net::HTTP.new(host, port) }
  let(:configuration_options) { {} }

  before do
    Datadog.configure { |c| c.tracing.instrument :http, configuration_options }
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:http].reset_configuration!
    example.run
    Datadog.registry[:http].reset_configuration!
  end

  context 'with custom error codes' do
    subject(:response) { client.get(path) }
    before { stub_request(:any, "#{uri}#{path}").to_return(status: status_code, body: '{}') }

    include_examples 'with error status code configuration'
  end

  describe '#get' do
    subject(:response) { client.get(path) }

    context 'that returns 200' do
      before { stub_request(:get, "#{uri}#{path}").to_return(status: 200, body: '{}') }

      let(:content) { JSON.parse(response.body) }

      it 'generates a well-formed trace' do
        expect(response.code).to eq('200')
        expect(content).to be_a_kind_of(Hash)
        expect(spans).to have(1).items
        expect(span.name).to eq('http.request')
        expect(span.service).to eq('net/http')
        expect(span.resource).to eq('GET')
        expect(span.get_tag('http.url')).to eq(path)
        expect(span.get_tag('http.method')).to eq('GET')
        expect(span.get_tag('http.status_code')).to eq('200')
        expect(span.get_tag('out.host')).to eq(host)
        expect(span.get_tag('out.port')).to eq(port.to_s)
        expect(span.get_tag('span.kind')).to eq('client')
        expect(span.status).to eq(0)
      end

      it_behaves_like 'analytics for integration' do
        let(:analytics_enabled_var) { Datadog::Tracing::Contrib::HTTP::Ext::ENV_ANALYTICS_ENABLED }
        let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::HTTP::Ext::ENV_ANALYTICS_SAMPLE_RATE }
        before { response }
      end

      it_behaves_like 'measured span for integration', false do
        before { response }
      end

      it_behaves_like 'a peer service span' do
        let(:peer_hostname) { host }
      end

      it_behaves_like 'environment service name', 'DD_TRACE_NET_HTTP_SERVICE_NAME'
    end

    context 'that returns 404' do
      before { stub_request(:get, "#{uri}#{path}").to_return(status: 404, body: body) }

      let(:body) { '{ "code": 404, message": "Not found!" }' }

      it 'generates a well-formed trace' do
        expect(response.code).to eq('404')
        expect(spans).to have(1).items
        expect(span.name).to eq('http.request')
        expect(span.service).to eq('net/http')
        expect(span.resource).to eq('GET')
        expect(span.get_tag('http.url')).to eq(path)
        expect(span.get_tag('http.method')).to eq('GET')
        expect(span.get_tag('http.status_code')).to eq('404')
        expect(span.get_tag('out.host')).to eq(host)
        expect(span.get_tag('out.port')).to eq(port.to_s)
        expect(span.get_tag('span.kind')).to eq('client')
        expect(span.status).to eq(1)
        expect(span.get_tag('error.type')).to eq('Net::HTTPNotFound')
        expect(span.get_tag('error.message')).to be nil
      end

      it_behaves_like 'a peer service span' do
        let(:peer_hostname) { host }
      end

      it_behaves_like 'environment service name', 'DD_TRACE_NET_HTTP_SERVICE_NAME'

      context 'when configured with #after_request hook' do
        before { Datadog::Tracing::Contrib::HTTP::Instrumentation.after_request(&callback) }

        after { Datadog::Tracing::Contrib::HTTP::Instrumentation.instance_variable_set(:@after_request, nil) }

        context 'which defines each parameter' do
          let(:callback) do
            proc do |span_op, http, request, response|
              expect(span_op).to be_a_kind_of(Datadog::Tracing::SpanOperation)
              expect(http).to be_a_kind_of(Net::HTTP)
              expect(request).to be_a_kind_of(Net::HTTP::Get)
              expect(response).to be_a_kind_of(Net::HTTPNotFound)
            end
          end

          it { expect(response.code).to eq('404') }
        end

        context 'which changes the error status' do
          let(:callback) do
            proc do |span_op, _http, _request, response|
              case response.code.to_i
              when 400...599
                if response.class.body_permitted? && !response.body.nil?
                  span_op.set_error([response.class, response.body[0...4095]])
                end
              end
            end
          end

          it 'generates a trace modified by the hook' do
            expect(response.code).to eq('404')
            expect(span.status).to eq(1)
            expect(span.get_tag('error.type')).to eq('Net::HTTPNotFound')
            expect(span.get_tag('error.message')).to eq(body)
          end
        end
      end
    end
  end

  describe '#post' do
    subject(:response) { client.post(path, payload) }

    let(:payload) { '{ "foo": "bar" }' }

    context 'that returns 201' do
      before { stub_request(:post, "#{uri}#{path}").to_return(status: 201) }

      it 'generates a well-formed trace' do
        expect(response.code).to eq('201')
        expect(spans).to have(1).items
        expect(span.name).to eq('http.request')
        expect(span.service).to eq('net/http')
        expect(span.resource).to eq('POST')
        expect(span.get_tag('http.url')).to eq(path)
        expect(span.get_tag('http.method')).to eq('POST')
        expect(span.get_tag('http.status_code')).to eq('201')
        expect(span.get_tag('out.host')).to eq(host)
        expect(span.get_tag('out.port')).to eq(port.to_s)
        expect(span.get_tag('span.kind')).to eq('client')
        expect(span.status).to eq(0)
      end

      it_behaves_like 'a peer service span' do
        let(:peer_hostname) { host }
      end

      it_behaves_like 'environment service name', 'DD_TRACE_NET_HTTP_SERVICE_NAME'
    end
  end

  describe '#start' do
    context 'which applies a pin to the Net::HTTP object' do
      before do
        stub_request(:get, "#{uri}#{path}").to_return(status: 200, body: '{}')

        Net::HTTP.start(host, port) do |http|
          http.request(request)
        end
      end

      let(:request) { Net::HTTP::Get.new(path) }

      it 'generates a well-formed trace' do
        expect(spans).to have(1).items
        expect(span.name).to eq('http.request')
        expect(span.service).to eq('net/http')
        expect(span.resource).to eq('GET')
        expect(span.get_tag('http.url')).to eq(path)
        expect(span.get_tag('http.method')).to eq('GET')
        expect(span.get_tag('http.status_code')).to eq('200')
        expect(span.get_tag('out.host')).to eq(host)
        expect(span.get_tag('out.port')).to eq(port.to_s)
        expect(span.get_tag('span.kind')).to eq('client')
        expect(span.status).to eq(0)
      end

      it_behaves_like 'a peer service span' do
        let(:peer_hostname) { host }
      end

      it_behaves_like 'environment service name', 'DD_TRACE_NET_HTTP_SERVICE_NAME'
    end
  end

  describe 'Net::HTTP object pin' do
    context 'when overriden with a different #service value' do
      subject(:response) { client.get(path) }

      before do
        stub_request(:get, "#{uri}#{path}").to_return(status: 200, body: '{}')
        Datadog.configure_onto(client, service_name: service_name)
      end

      let(:service_name) { 'bar' }

      it 'generates a well-formed trace' do
        expect(response.code).to eq('200')
        expect(spans).to have(1).items
        expect(span.name).to eq('http.request')
        expect(span.service).to eq(service_name)
        expect(span.get_tag('span.kind')).to eq('client')
      end

      it_behaves_like 'a peer service span' do
        let(:peer_hostname) { host }
      end
    end
  end

  context 'when split by domain' do
    subject(:response) { client.get(path) }

    let(:configuration_options) { super().merge(split_by_domain: true) }

    before { stub_request(:get, "#{uri}#{path}").to_return(status: 200, body: '{}') }

    it do
      response
      expect(span.name).to eq(Datadog::Tracing::Contrib::HTTP::Ext::SPAN_REQUEST)
      expect(span.service).to eq(host)
      expect(span.resource).to eq('GET')
      expect(span.get_tag('span.kind')).to eq('client')
    end

    context 'and the host matches a specific configuration' do
      before do
        Datadog.configure do |c|
          c.tracing.instrument :http, configuration_options
          c.tracing.instrument :http, describes: /127.0.0.1/ do |http|
            http.service_name = 'bar'
            http.split_by_domain = false
          end

          c.tracing.instrument :http, describes: /badexample\.com/ do |http|
            http.service_name = 'bar_bad'
            http.split_by_domain = false
          end
        end
      end

      it 'uses the configured service name over the domain name and the correct describes block' do
        response
        expect(span.service).to eq('bar')
        expect(span.get_tag('span.kind')).to eq('client')
      end
    end
  end

  describe 'distributed tracing' do
    before do
      stub_request(:get, "#{uri}#{path}").to_return(status: 200, body: '{}')
    end

    def expect_request_without_distributed_headers
      # rubocop:disable Style/BlockDelimiters
      expect(WebMock).to(
        have_requested(:get, "#{uri}#{path}").with { |req|
          %w[
            x-datadog-parent-id
            x-datadog-trace-id
            x-datadog-sampling-priority
          ].none? do |header|
            req.headers.key?(header.split('-').map(&:capitalize).join('-'))
          end
        }
      )
    end

    context 'by default' do
      context 'and the tracer is enabled' do
        before do
          tracer.trace('foo.bar') do |_span, trace|
            trace.sampling_priority = sampling_priority
            client.get(path)
          end
        end

        let(:sampling_priority) { 10 }
        let(:distributed_tracing_headers) do
          {
            'x-datadog-parent-id' => span.span_id,
            'x-datadog-trace-id' => span.trace_id,
            'x-datadog-sampling-priority' => sampling_priority
          }
        end

        let(:span) { spans.last }

        it 'adds distributed tracing headers' do
          # The block syntax only works with Ruby < 2.3 and the hash syntax
          # only works with Ruby >= 2.3, so we need to support both.
          if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.3.0')
            expect(WebMock).to(
              have_requested(:get, "#{uri}#{path}").with { |req|
                distributed_tracing_headers.all? do |(header, value)|
                  req.headers[header.split('-').map(&:capitalize).join('-')] == value.to_s
                end
              }
            )
          else
            expect(WebMock).to have_requested(:get, "#{uri}#{path}").with(headers: distributed_tracing_headers)
          end
        end
      end

      # This can happen if another http client uses net/http (e.g. restclient)
      # The goal here is to ensure we do not add multiple values for a given header
      context 'with existing distributed tracing headers' do
        before do
          tracer.trace('foo.bar') do |_span, trace|
            trace.sampling_priority = sampling_priority

            req = Net::HTTP::Get.new(path)
            req['x-datadog-parent-id'] = 100
            req['x-datadog-trace-id'] = 100
            req['x-datadog-sampling-priority'] = 0

            Net::HTTP.start(host, port) do |http|
              http.request(req)
            end
          end
        end

        let(:sampling_priority) { 10 }
        let(:distributed_tracing_headers) do
          {
            'x-datadog-parent-id' => span.span_id,
            'x-datadog-trace-id' => span.trace_id,
            'x-datadog-sampling-priority' => sampling_priority
          }
        end

        let(:span) { spans.last }

        it 'adds distributed tracing headers' do
          # The block syntax only works with Ruby < 2.3 and the hash syntax
          # only works with Ruby >= 2.3, so we need to support both.
          if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.3.0')
            expect(WebMock).to(
              have_requested(:get, "#{uri}#{path}").with { |req|
                distributed_tracing_headers.all? do |(header, value)|
                  req.headers[header.split('-').map(&:capitalize).join('-')] == value.to_s
                end
              }
            )
          else
            expect(WebMock).to have_requested(:get, "#{uri}#{path}").with(headers: distributed_tracing_headers)
          end
        end
      end

      context 'but the tracer is disabled' do
        before do
          Datadog.configure do |c|
            c.tracing.enabled = false
          end

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
        Datadog.configure { |c| c.tracing.instrument :http, distributed_tracing: false }
        client.get(path)
      end

      after do
        Datadog.configure { |c| c.tracing.instrument :http, distributed_tracing: true }
      end

      let(:span) { spans.last }

      it 'does not add distributed tracing headers' do
        expect(span.name).to eq('http.request')
        expect_request_without_distributed_headers
      end
    end
  end

  describe 'request exceptions' do
    subject(:response) { client.get(path) }

    context 'that raises a timeout' do
      let(:timeout_error) { Net::OpenTimeout.new('execution expired') }

      before { stub_request(:get, "#{uri}#{path}").to_raise(timeout_error) }

      it 'generates a well-formed trace with span tags available from request object' do
        expect { response }.to raise_error(timeout_error)
        expect(spans).to have(1).items
        expect(span.name).to eq('http.request')
        expect(span.service).to eq('net/http')
        expect(span.resource).to eq('GET')
        expect(span.get_tag('http.url')).to eq(path)
        expect(span.get_tag('http.method')).to eq('GET')
        expect(span.get_tag('out.host')).to eq(host)
        expect(span.get_tag('out.port')).to eq(port.to_s)
        expect(span.get_tag('span.kind')).to eq('client')
        expect(span).to have_error
        expect(span).to have_error_type(timeout_error.class.to_s)
        expect(span).to have_error_message(timeout_error.message)
      end

      it_behaves_like 'environment service name', 'DD_TRACE_NET_HTTP_SERVICE_NAME', error: Net::OpenTimeout
    end

    context 'that raises an error' do
      let(:custom_error_message) { 'example error' }
      let(:custom_error) { StandardError.new(custom_error_message) }

      before { stub_request(:get, "#{uri}#{path}").to_raise(custom_error) }

      it 'generates a well-formed trace with span tags available from request object' do
        expect { response }.to raise_error(custom_error)
        expect(spans).to have(1).items
        expect(span.name).to eq('http.request')
        expect(span.service).to eq('net/http')
        expect(span.resource).to eq('GET')
        expect(span.get_tag('http.url')).to eq(path)
        expect(span.get_tag('http.method')).to eq('GET')
        expect(span.get_tag('out.host')).to eq(host)
        expect(span.get_tag('out.port')).to eq(port.to_s)
        expect(span.get_tag('span.kind')).to eq('client')
        expect(span).to have_error
        expect(span).to have_error_type(custom_error.class.to_s)
        expect(span).to have_error_message(custom_error.message)
      end

      it_behaves_like 'environment service name', 'DD_TRACE_NET_HTTP_SERVICE_NAME', error: StandardError
    end
  end

  context 'when basic auth in url' do
    before do
      WebMock.enable!
      stub_request(:get, /example.com/).to_return(status: 200)
    end

    after { WebMock.disable! }

    it 'does not collect auth info' do
      uri = URI('http://username:password@example.com/sample/path')

      Net::HTTP.get_response(uri)

      expect(span.get_tag('http.url')).to eq('/sample/path')
      expect(span.get_tag('out.host')).to eq('example.com')
    end
  end
end
