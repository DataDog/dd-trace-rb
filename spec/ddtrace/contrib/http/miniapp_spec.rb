require 'ddtrace/contrib/integration_examples'
require 'ddtrace/contrib/support/spec_helper'
require 'ddtrace'
require 'net/http'
require 'time'
require_relative './test_http_server'

RSpec.describe 'net/http miniapp tests' do
  let(:host) { '127.0.0.1' }
  let(:port) { 1234 }
  let(:uri) { "http://#{host}:#{port}" }

  context 'when performing a trace around HTTP calls' do
    let(:server) { TestHTTPServer.new host, port }

    before do
      server
      original_verbosity = $VERBOSE
      $VERBOSE = nil
      Net.send(:const_set, :HTTP, ::OriginalNetHTTP)
      $VERBOSE = original_verbosity

      Datadog::Contrib::HTTP::Patcher.remove_instance_variable(:@done_once) if Datadog::Contrib::HTTP::Patcher.patched?
      Datadog.configure { |c| c.use :http }
    end

    after do
      server.close
    end

    let(:client) { Net::HTTP.new(host, port) }

    shared_examples_for 'a trace with connection and two HTTP requests spans' do
      before do
        tracer.trace('page') do |span|
          span.service = 'webapp'
          span.resource = '/index'

          http_calls
        end

        expect(server.requests_paths).to eq ["GET /my/path HTTP/1.1", "GET /my/path HTTP/1.1"]
      end

      let(:connect_count) { 1 }
      let(:path) { '/my/path' }
      let(:parent_span) { spans.last }
      let(:connect_spans) { spans[0..connect_count-1] }
      let(:request_spans) { spans[connect_count..-2] }
      let(:trace_id) { parent_span.trace_id }
      let(:span_id) { parent_span.span_id }

      it 'generates a trace with connection and two request spans' do
        expect(spans).to have(connect_count + 3).items
        expect(spans.map {|span| span.name}).to eq(connect_count.times.map { "http.connect" } + ["http.request", "http.request", "page"])

        # Parent span
        expect(parent_span.name).to eq('page')
        expect(parent_span.service).to eq('webapp')
        expect(parent_span.resource).to eq('/index')
        expect(parent_span.span_id).to_not eq(parent_span.trace_id)
        expect(parent_span.parent_id).to eq(0)

        # Connect span
        connect_spans.each do |span|
          expect(span.name).to eq('http.connect')
          expect(span.service).to eq('net/http')
          expect(span.resource).to eq("#{host}:#{port}")
          expect(span.parent_id).to eq(parent_span.span_id)
          expect(span.trace_id).to eq(trace_id)
        end

        # HTTP Spans
        request_spans.each do |span|
          expect(span.name).to eq('http.request')
          expect(span.service).to eq('net/http')
          expect(span.get_tag(Datadog::Ext::Integration::TAG_PEER_SERVICE)).to eq('net/http')
          expect(span.resource).to eq('GET')
          expect(span.get_tag('http.url')).to eq('/my/path')
          expect(span.get_tag('http.method')).to eq('GET')
          expect(span.get_tag('http.status_code')).to eq('200')
          expect(span.parent_id).to eq(parent_span.span_id)
          expect(span.trace_id).to eq(trace_id)
        end
      end
    end

    context 'which use #get' do
      it_behaves_like 'a trace with connection and two HTTP requests spans' do
        # client.get closes connection after the call, so the second call opens second connection
        let(:connect_count) { 2 }
        let(:http_calls) do
          2.times do
            client.get('/my/path')
          end
        end
      end
    end

    context 'which use #get when connection opened' do
      it_behaves_like 'a trace with connection and two HTTP requests spans' do
        let(:http_calls) do
          client.start
          2.times do
            client.get('/my/path')
          end
          client.finish
        end
      end
    end

    context 'which use a block' do
      it_behaves_like 'a trace with connection and two HTTP requests spans' do
        let(:http_calls) do
          Net::HTTP.start(host, port) do |http|
            2.times do
              http.request(Net::HTTP::Get.new(path))
            end
          end
        end
      end
    end
  end

  context 'when error during connection' do
    let(:host) { 'nonexisting.dns.name.ddtrace.example.local' }
    let(:client) { Net::HTTP.new(host, port) }

    before do
      original_verbosity = $VERBOSE
      $VERBOSE = nil
      Net.send(:const_set, :HTTP, ::OriginalNetHTTP)
      $VERBOSE = original_verbosity

      Datadog::Contrib::HTTP::Patcher.remove_instance_variable(:@done_once) if Datadog::Contrib::HTTP::Patcher.patched?
      Datadog.configure { |c| c.use :http }
    end

    before do
      allow(TCPSocket).to receive(:open)
        .and_raise(SocketError, 'getaddrinfo: nodename nor servname provided, or not known')
    end

    shared_examples_for 'a connection error trace' do
      before do
        tracer.trace('page') do |span|
          span.service = 'webapp'
          span.resource = '/index'

          http_calls
        end
      end

      let(:path) { '/my/path' }
      let(:parent_span) { spans[1] }
      let(:http_spans) { spans[0..0] }
      let(:trace_id) { spans[1].trace_id }
      let(:span_id) { spans[1].span_id }

      it 'generates a complete trace' do
        expect(spans).to have(2).items

        # Parent span
        expect(parent_span.name).to eq('page')
        expect(parent_span.service).to eq('webapp')
        expect(parent_span.resource).to eq('/index')
        expect(parent_span.span_id).to_not eq(parent_span.trace_id)
        expect(parent_span.parent_id).to eq(0)

        # HTTP Spans
        http_spans.each do |span|
          expect(span.name).to eq('http.connect')
          expect(span.service).to eq('net/http')
          expect(span.get_tag(Datadog::Ext::Integration::TAG_PEER_SERVICE)).to eq('net/http')
          expect(span.resource).to eq(expected_resource)
          expect(span.parent_id).to eq(parent_span.span_id)
          expect(span.trace_id).to eq(trace_id)
          expect(span.get_tag(Datadog::Ext::Errors::TYPE)).to eq('SocketError')
        end
      end
    end

    context 'which use #get' do
      it_behaves_like 'a connection error trace' do
        let(:expected_resource) { "#{host}:#{port}" }
        let(:http_calls) do
          expect { client.get('/my/path') }.to raise_error(SocketError)
        end
      end
    end

    context 'which use ::get' do
      it_behaves_like 'a connection error trace' do
        let(:expected_resource) { "#{host}:#{port}" }
        let(:http_calls) do
          expect { Net::HTTP.get(host, '/my/path', port) }.to raise_error(SocketError)
        end
      end
    end

    context 'which use a block' do
      it_behaves_like 'a connection error trace' do
        let(:expected_resource) { "#{host}:#{port}" }
        let(:http_calls) do
          expect do
            Net::HTTP.start(host, port) do |http|
              http.request(Net::HTTP::Get.new(path))
            end
          end.to raise_error(SocketError)
        end
      end
    end

    context 'which use a start without block' do
      it_behaves_like 'a connection error trace' do
        let(:expected_resource) { "#{host}:#{port}" }
        let(:http_calls) do
          expect do
            begin
              http = Net::HTTP.start(host, port)
              http.request(Net::HTTP::Get.new(path))
            ensure
              http.finish unless http.nil?
            end
          end.to raise_error(SocketError)
        end
      end
    end
  end
end
