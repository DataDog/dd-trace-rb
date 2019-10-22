require 'spec_helper'
require 'ddtrace'
require 'httparty'

RSpec.describe 'ExampleClient' do
  let(:tracer) { get_test_tracer }
  let(:configuration_options) { { tracer: tracer } }

  before do
    Datadog.configure do |c|
      c.use :httparty, configuration_options
    end

    WebMock.disable_net_connect!
    WebMock.enable!
  end

  let(:klass) do
    Class.new do
      include HTTParty
      base_uri 'https://example.com'
      ddtrace_options service_name: 'foo_service'

      def foo
        self.class.get('/foo')
      end
    end
  end

  describe '.foo' do
    let(:status) { 200 }
    let(:uri) { URI.parse("#{klass.base_uri}/foo") }

    subject(:request) { klass.new.foo }

    before do
      stub_request(:get, uri).to_return(status: status, body: 'ok')
    end

    it 'creates a span' do
      expect { request }.to change { tracer.writer.spans.first }.to be_instance_of(Datadog::Span)
    end

    describe 'created span' do
      subject(:span) { tracer.writer.spans.first }

      before { request }

      it 'has tag with target host' do
        expect(span.get_tag(Datadog::Ext::NET::TARGET_HOST)).to eq(uri.host)
      end

      it 'has tag with target port' do
        expect(span.get_tag(Datadog::Ext::NET::TARGET_PORT)).to eq(uri.port.to_s)
      end

      it 'has tag with target method' do
        expect(span.get_tag(Datadog::Ext::HTTP::METHOD)).to eq('GET')
      end

      it 'has tag with target path' do
        expect(span.get_tag(Datadog::Ext::HTTP::URL)).to eq(uri.path)
      end

      it 'has tag with status code' do
        expect(span.get_tag(Datadog::Ext::HTTP::STATUS_CODE)).to eq(status.to_s)
      end

      it 'is http type' do
        expect(span.span_type).to eq('http')
      end

      it 'is named correctly' do
        expect(span.name).to eq('httparty.request')
      end

      it 'has correct service name' do
        expect(span.service).to eq('foo_service')
      end
    end
  end
end
