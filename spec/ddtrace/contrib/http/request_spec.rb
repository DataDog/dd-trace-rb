require 'spec_helper'
require 'ddtrace/contrib/analytics_examples'

require 'ddtrace'
require 'net/http'
require 'time'
require 'json'

RSpec.describe 'net/http requests' do
  before(:each) { WebMock.enable! }
  after(:each) do
    WebMock.reset!
    WebMock.disable!
  end

  let(:host) { '127.0.0.1' }
  let(:port) { 1234 }
  let(:uri) { "http://#{host}:#{port}" }

  let(:client) { Net::HTTP.new(host, port) }
  let(:tracer) { get_test_tracer }
  let(:configuration_options) { { tracer: tracer } }

  let(:spans) { tracer.writer.spans }

  before(:each) do
    Datadog.configure { |c| c.use :http, configuration_options }
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:http].reset_configuration!
    example.run
    Datadog.registry[:http].reset_configuration!
  end

  describe '#get' do
    subject(:response) { client.get(path) }
    let(:path) { '/my/path' }

    context 'that returns 200' do
      before(:each) { stub_request(:get, "#{uri}#{path}").to_return(status: 200, body: '{}') }
      let(:content) { JSON.parse(response.body) }
      let(:span) { spans.first }

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
        expect(span.status).to eq(0)
      end

      it_behaves_like 'analytics for integration' do
        let(:analytics_enabled_var) { Datadog::Contrib::HTTP::Ext::ENV_ANALYTICS_ENABLED }
        let(:analytics_sample_rate_var) { Datadog::Contrib::HTTP::Ext::ENV_ANALYTICS_SAMPLE_RATE }
        before(:each) { response }
      end
    end

    context 'that returns 404' do
      before(:each) { stub_request(:get, "#{uri}#{path}").to_return(status: 404) }
      let(:span) { spans.first }

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
        expect(span.status).to eq(1)
        expect(span.get_tag('error.type')).to eq('Net::HTTPNotFound')
      end
    end
  end

  describe '#post' do
    subject(:response) { client.post(path, payload) }
    let(:path) { '/my/path' }
    let(:payload) { '{ "foo": "bar" }' }

    context 'that returns 201' do
      before(:each) { stub_request(:post, "#{uri}#{path}").to_return(status: 201) }
      let(:span) { spans.first }

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
        expect(span.status).to eq(0)
      end
    end
  end

  describe '#start' do
    context 'which applies a pin to the Net::HTTP object' do
      before(:each) do
        stub_request(:get, "#{uri}#{path}").to_return(status: 200, body: '{}')

        Net::HTTP.start(host, port) do |http|
          Datadog::Pin.get_from(http).tracer = tracer
          http.request(request)
        end
      end

      let(:request) { Net::HTTP::Get.new(path) }
      let(:path) { '/my/path' }
      let(:span) { spans.first }

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
        expect(span.status).to eq(0)
      end
    end
  end

  describe 'Net::HTTP object pin' do
    context 'when overriden with a different #service value' do
      subject(:response) { client.get(path) }

      before(:each) do
        stub_request(:get, "#{uri}#{path}").to_return(status: 200, body: '{}')
        Datadog::Pin.get_from(client).service = service_name
      end

      let(:path) { '/my/path' }
      let(:service_name) { 'bar' }
      let(:span) { spans.first }

      it 'generates a well-formed trace' do
        expect(response.code).to eq('200')
        expect(spans).to have(1).items
        expect(span.name).to eq('http.request')
        expect(span.service).to eq(service_name)
      end
    end
  end

  describe 'distributed tracing' do
    let(:path) { '/my/path' }

    before(:each) do
      stub_request(:get, "#{uri}#{path}").to_return(status: 200, body: '{}')
    end

    def expect_request_without_distributed_headers
      # rubocop:disable Style/BlockDelimiters
      expect(WebMock).to(have_requested(:get, "#{uri}#{path}").with { |req|
        [
          Datadog::Ext::DistributedTracing::HTTP_HEADER_PARENT_ID,
          Datadog::Ext::DistributedTracing::HTTP_HEADER_TRACE_ID,
          Datadog::Ext::DistributedTracing::HTTP_HEADER_SAMPLING_PRIORITY
        ].none? do |header|
          req.headers.key?(header.split('-').map(&:capitalize).join('-'))
        end
      })
    end

    context 'by default' do
      context 'and the tracer is enabled' do
        before(:each) do
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
          # The block syntax only works with Ruby < 2.3 and the hash syntax
          # only works with Ruby >= 2.3, so we need to support both.
          if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.3.0')
            expect(WebMock).to(have_requested(:get, "#{uri}#{path}").with { |req|
              distributed_tracing_headers.all? do |(header, value)|
                req.headers[header.split('-').map(&:capitalize).join('-')] == value
              end
            })
          else
            expect(WebMock).to have_requested(:get, "#{uri}#{path}").with(headers: distributed_tracing_headers)
          end
        end
      end

      context 'but the tracer is disabled' do
        before(:each) do
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
      before(:each) do
        Datadog.configure { |c| c.use :http, distributed_tracing: false }
        client.get(path)
      end
      after(:each) do
        Datadog.configure { |c| c.use :http, distributed_tracing: true }
      end

      let(:span) { spans.last }

      it 'does not add distributed tracing headers' do
        expect(span.name).to eq('http.request')
        expect_request_without_distributed_headers
      end
    end
  end
end
