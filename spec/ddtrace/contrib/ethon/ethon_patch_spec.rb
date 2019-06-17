require 'spec_helper'
require 'ddtrace/contrib/analytics_examples'

require 'ddtrace'
require 'ddtrace/contrib/ethon/easy_patch'
require 'ddtrace/contrib/ethon/multi_patch'
require 'typhoeus'
require 'stringio'
require 'webrick'

RSpec.describe Datadog::Contrib::Ethon do
  let(:tracer) { get_test_tracer }
  let(:configuration_options) { { tracer: tracer } }

  before(:all) do
    @port = 6220
    @log_buffer = StringIO.new # set to $stderr to debug
    log = WEBrick::Log.new(@log_buffer, WEBrick::Log::DEBUG)
    access_log = [[@log_buffer, WEBrick::AccessLog::COMBINED_LOG_FORMAT]]

    server = WEBrick::HTTPServer.new(Port: @port, Logger: log, AccessLog: access_log)
    server.mount_proc '/' do |req, res|
      sleep(1) if req.query['simulate_timeout']
      res.status = (req.query['status'] || req.body['status']).to_i
      if req.query['return_headers']
        headers = {}
        req.each do |header_name|
          headers[header_name] = req.header[header_name]
        end
        res.body = JSON.generate(headers: headers)
      else
        res.body = 'response'
      end
    end
    Thread.new { server.start }
    @server = server
  end
  after(:all) { @server.shutdown }

  let(:host) { 'localhost' }
  let(:status) { '200' }
  let(:path) { '/sample/path' }
  let(:method) { 'GET' }
  let(:simulate_timeout) { false }
  let(:timeout) { 0.5 }
  let(:return_headers) { false }
  let(:query) do
    query = { status: status }
    query[:return_headers] = 'true' if return_headers
    query[:simulate_timeout] = 'true' if simulate_timeout
  end
  let(:url) do
    url = "http://#{host}:#{@port}#{path}?"
    url += "status=#{status}&" if status
    url += 'return_headers=true&' if return_headers
    url += 'simulate_timeout=true' if simulate_timeout
    url
  end

  before do
    Datadog.configure do |c|
      c.use :ethon, configuration_options
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:ethon].reset_configuration!
    example.run
    Datadog.registry[:ethon].reset_configuration!
  end

  describe 'instrumented request' do
    shared_examples_for 'span' do
      it 'has tag with target host' do
        expect(span.get_tag(Datadog::Ext::NET::TARGET_HOST)).to eq(host)
      end

      it 'has tag with target port' do
        expect(span.get_tag(Datadog::Ext::NET::TARGET_PORT)).to eq(@port.to_s)
      end

      it 'has tag with method' do
        expect(span.get_tag(Datadog::Ext::HTTP::METHOD)).to eq(method)
      end

      it 'has tag with URL' do
        expect(span.get_tag(Datadog::Ext::HTTP::URL)).to eq(path)
      end

      it 'has tag with status code' do
        expect(span.get_tag(Datadog::Ext::HTTP::STATUS_CODE)).to eq(status)
      end

      it 'is http type' do
        expect(span.span_type).to eq('http')
      end

      it 'is named correctly' do
        expect(span.name).to eq('ethon.request')
      end

      it 'has correct service name' do
        expect(span.service).to eq('ethon')
      end
    end

    shared_examples_for 'instrumented request' do
      it 'creates a span' do
        expect { request }.to change { tracer.writer.spans.first }.to be_instance_of(Datadog::Span)
      end

      it 'returns response' do
        expect(request.body).to eq('response')
      end

      describe 'created span' do
        subject(:span) { tracer.writer.spans.first }

        context 'response is successfull' do
          before { request }

          it_behaves_like 'span'

          it_behaves_like 'analytics for integration' do
            let(:analytics_enabled_var) { Datadog::Contrib::Ethon::Ext::ENV_ANALYTICS_ENABLED }
            let(:analytics_sample_rate_var) { Datadog::Contrib::Ethon::Ext::ENV_ANALYTICS_SAMPLE_RATE }
          end
        end

        context 'response has internal server error status' do
          let(:status) { 500 }

          before { request }

          it 'has tag with status code' do
            expect(span.get_tag(Datadog::Ext::HTTP::STATUS_CODE)).to eq(status.to_s)
          end

          it 'has error set' do
            expect(span.get_tag(Datadog::Ext::Errors::MSG)).to eq('Request has failed with HTTP error: 500')
          end
          it 'has no error stack' do
            expect(span.get_tag(Datadog::Ext::Errors::STACK)).to be_nil
          end
          it 'has no error type' do
            expect(span.get_tag(Datadog::Ext::Errors::TYPE)).to be_nil
          end
        end

        context 'response has not found status' do
          let(:status) { 404 }

          before { request }

          it 'has tag with status code' do
            expect(span.get_tag(Datadog::Ext::HTTP::STATUS_CODE)).to eq(status.to_s)
          end

          it 'has no error set' do
            expect(span.get_tag(Datadog::Ext::Errors::MSG)).to be_nil
          end
        end

        context 'request timed out' do
          let(:simulate_timeout) { true }

          before { request }

          it 'has no status code set' do
            expect(span.get_tag(Datadog::Ext::HTTP::STATUS_CODE)).to be_nil
          end

          it 'has error set' do
            expect(span.get_tag(Datadog::Ext::Errors::MSG)).to eq('Request has failed: Timeout was reached')
          end
        end
      end

      context 'distributed tracing default' do
        let(:return_headers) { true }
        let(:span) { tracer.writer.spans.first }

        shared_examples_for 'propagating distributed headers' do
          let(:return_headers) { true }
          let(:span) { tracer.writer.spans.first }

          it 'propagates the headers' do
            response = request
            headers = JSON.parse(response.body)['headers']
            distributed_tracing_headers = {
              'x-datadog-parent-id' => [span.span_id.to_s],
              'x-datadog-trace-id' => [span.trace_id.to_s]
            }

            expect(headers).to include(distributed_tracing_headers)
          end
        end

        it_behaves_like 'propagating distributed headers'

        context 'with sampling priority' do
          let(:return_headers) { true }
          let(:sampling_priority) { 0.2 }

          before do
            tracer.provider.context.sampling_priority = sampling_priority
          end

          it_behaves_like 'propagating distributed headers'

          it 'propagates sampling priority' do
            response = request
            headers = JSON.parse(response.body)['headers']

            expect(headers).to include('x-datadog-sampling-priority' => [sampling_priority.to_s])
          end
        end
      end
    end

    context 'with Easy request' do
      subject(:request) do
        easy = Ethon::Easy.new
        easy.http_request(url, 'GET', params: query, timeout_ms: timeout * 1000)
        easy.perform
        # Use Typhoeus response to make life easier
        Typhoeus::Response.new(easy.mirror.options)
      end

      it_behaves_like 'instrumented request'

      context 'distributed tracing disabled' do
        let(:configuration_options) { super().merge(distributed_tracing: false) }

        shared_examples_for 'does not propagate distributed headers' do
          let(:return_headers) { true }

          it 'does not propagate the headers' do
            response = request
            headers = JSON.parse(response.body)['headers']

            expect(headers).not_to include('x-datadog-parent-id', 'x-datadog-trace-id')
          end
        end

        it_behaves_like 'does not propagate distributed headers'

        context 'with sampling priority' do
          let(:return_headers) { true }
          let(:sampling_priority) { 0.2 }

          before do
            tracer.provider.context.sampling_priority = sampling_priority
          end

          it_behaves_like 'does not propagate distributed headers'

          it 'does not propagate sampling priority headers' do
            response = request
            headers = JSON.parse(response.body)['headers']

            expect(headers).not_to include('x-datadog-sampling-priority')
          end
        end
      end
    end

    context 'with simple easy & headers override' do
      subject(:request) do
        easy = Ethon::Easy.new(url: url)
        easy.customrequest = 'GET'
        easy.set_attributes(timeout_ms: timeout * 1000)
        easy.headers = {}
        easy.perform
        # Use Typhoeus response to make life easier
        Typhoeus::Response.new(easy.mirror.options)
      end

      it_behaves_like 'instrumented request' do
        let(:method) { '' }
      end
    end

    context 'with single Multi request' do
      subject(:request) do
        multi = Ethon::Multi.new
        easy = Ethon::Easy.new
        easy.http_request(url, 'GET', params: query, timeout_ms: timeout * 1000)
        multi.add(easy)
        multi.perform
        Typhoeus::Response.new(easy.mirror.options)
      end

      it_behaves_like 'instrumented request'
    end

    context 'with Typhoeus request' do
      subject(:request) { Typhoeus::Request.new(url, timeout: timeout).run }

      it_behaves_like 'instrumented request'
    end

    context 'with single Hydra request' do
      subject(:request) do
        hydra = Typhoeus::Hydra.new
        request = Typhoeus::Request.new(url, timeout: timeout)
        hydra.queue(request)
        hydra.run
        request.response
      end

      it_behaves_like 'instrumented request'
    end

    context 'with concurrent Hydra requests' do
      let(:url_1) { "http://#{host}:#{@port}#{path}?status=200&simulate_timeout=true" }
      let(:url_2) { "http://#{host}:#{@port}#{path}" }
      let(:request_1) { Typhoeus::Request.new(url_1, timeout: timeout) }
      let(:request_2) { Typhoeus::Request.new(url_2, method: :post, timeout: timeout, body: { status: 404 }) }
      subject(:request) do
        hydra = Typhoeus::Hydra.new
        hydra.queue(request_1)
        hydra.queue(request_2)
        hydra.run
      end

      it 'creates 2 spans' do
        expect { request }.to change { tracer.writer.spans.count }.to 2
      end

      describe 'created spans' do
        subject(:spans) { tracer.writer.spans }
        let(:span_get) { spans.select { |span| span.get_tag(Datadog::Ext::HTTP::METHOD) == 'GET' }.first }
        let(:span_post) { spans.select { |span| span.get_tag(Datadog::Ext::HTTP::METHOD) == 'POST' }.first }

        before { request }

        it_behaves_like 'span' do
          let(:span) { span_get }
          let(:status) { nil }
        end

        it_behaves_like 'span' do
          let(:span) { span_post }
          let(:status) { '404' }
          let(:method) { 'POST' }
        end

        it 'has timeout set on GET request span' do
          expect(span_get.get_tag(Datadog::Ext::Errors::MSG)).to eq('Request has failed: Timeout was reached')
        end
      end
    end
  end
end
