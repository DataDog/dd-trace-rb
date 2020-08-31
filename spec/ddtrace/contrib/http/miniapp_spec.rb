require 'ddtrace/contrib/support/spec_helper'
require 'ddtrace'
require 'net/http'
require 'time'

RSpec.describe 'net/http miniapp tests' do
  before(:each) { WebMock.enable! }
  after(:each) do
    WebMock.reset!
    WebMock.disable!
  end

  let(:host) { '127.0.0.1' }
  let(:port) { 1234 }
  let(:uri) { "http://#{host}:#{port}" }

  let(:client) { Net::HTTP.new(host, port) }
  before(:each) do
    Datadog.configure { |c| c.use :http }
  end

  context 'when performing a trace around HTTP calls' do
    before(:each) do
      stub_request(:get, %r{#{uri}/.*}).to_return(body: '{}')
    end

    shared_examples_for 'a trace with two HTTP calls' do
      before(:each) do
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
end
