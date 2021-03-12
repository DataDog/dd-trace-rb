require 'ddtrace/contrib/integration_examples'
require 'ddtrace/contrib/support/spec_helper'
require 'ddtrace'
require 'net/http'
require 'time'

RSpec.describe 'net/http miniapp tests' do
  let(:host) { '127.0.0.1' }
  let(:port) { 1234 }
  let(:uri) { "http://#{host}:#{port}" }

  context 'when performing a trace around HTTP calls' do
    before { WebMock.enable! }

    after do
      WebMock.reset!
      WebMock.disable!
      Datadog::Contrib::HTTP::Patcher.remove_instance_variable(:@done_once) if Datadog::Contrib::HTTP::Patcher.patched?
    end

    let(:client) { Net::HTTP.new(host, port) }

    before do
      Datadog::Contrib::HTTP::Patcher.remove_instance_variable(:@done_once) if Datadog::Contrib::HTTP::Patcher.patched?
      Datadog.configure { |c| c.use :http }
    end

    before do
      stub_request(:get, %r{#{uri}/.*}).to_return(body: '{}')
    end

    shared_examples_for 'a trace with two HTTP calls' do
      before do
        tracer.trace('page') do |span|
          span.service = 'webapp'
          span.resource = '/index'

          http_calls
        end

        expect(WebMock).to have_requested(:get, "#{uri}#{path}").twice
      end

      let(:path) { '/my/path' }
      let(:parent_span) { spans[2] }
      let(:http_spans) { spans[0..1] }
      let(:trace_id) { spans[2].trace_id }
      let(:span_id) { spans[2].span_id }

      it 'generates a complete trace' do
        expect(spans).to have(3).items

        # Parent span
        expect(parent_span.name).to eq('page')
        expect(parent_span.service).to eq('webapp')
        expect(parent_span.resource).to eq('/index')
        expect(parent_span.span_id).to_not eq(parent_span.trace_id)
        expect(parent_span.parent_id).to eq(0)

        # HTTP Spans
        http_spans.each do |span|
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
      it_behaves_like 'a trace with two HTTP calls' do
        let(:http_calls) do
          2.times { client.get('/my/path') }
        end
      end
    end

    context 'which use a block' do
      it_behaves_like 'a trace with two HTTP calls' do
        let(:http_calls) do
          Net::HTTP.start(host, port) do |http|
            2.times { http.request(Net::HTTP::Get.new(path)) }
          end
        end
      end
    end
  end

  context 'when error during connection' do
    let(:host) { 'nonexisting.dns.name.ddtrace.example.local' }
    let(:client) { Net::HTTP.new(host, port) }

    before do
      Net.send(:const_set, :HTTP, ::OriginalNetHTTP)

      Datadog::Contrib::HTTP::Patcher.remove_instance_variable(:@done_once) if Datadog::Contrib::HTTP::Patcher.patched?
      Datadog.configure { |c| c.use :http }
    end

    after do
      Net.send(:const_set, :HTTP, ::OriginalNetHTTP)
      Datadog::Contrib::HTTP::Patcher.remove_instance_variable(:@done_once) if Datadog::Contrib::HTTP::Patcher.patched?
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
          expect(span.name).to eq('http.request')
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
        let(:expected_resource) { 'GET' }
        let(:http_calls) do
          expect { client.get('/my/path') }.to raise_error(SocketError)
        end
      end
    end

    context 'which use ::get' do
      it_behaves_like 'a connection error trace' do
        let(:expected_resource) { 'UNKNOWN' }
        let(:http_calls) do
          expect { Net::HTTP.get(host, '/my/path', port) }.to raise_error(SocketError)
        end
      end
    end

    context 'which use a block' do
      it_behaves_like 'a connection error trace' do
        let(:expected_resource) { 'UNKNOWN' }
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
        let(:expected_resource) { 'UNKNOWN' }
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
