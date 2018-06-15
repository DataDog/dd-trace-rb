require 'spec_helper'
require 'ddtrace'
require 'ddtrace/contrib/rest_client/request_patch'
require 'rest_client'

RSpec.describe Datadog::Contrib::RestClient::RequestPatch do
  let(:tracer) { Datadog::Tracer.new(writer: FauxWriter.new) }

  before do
    Datadog.configure do |c|
      c.use :rest_client, tracer: tracer
    end

    WebMock.disable_net_connect!
    WebMock.enable!
  end

  describe 'a' do
    let(:path) { '/sample/path' }
    let(:host) { 'example.com' }
    let(:url) { "http://#{host}#{path}"  }

    subject(:request) { RestClient.get(url) }

    before do
      stub_request(:get, url)
    end

    it 'creates a span' do
      expect { request }.to change { tracer.writer.spans.first }.to be_instance_of(Datadog::Span)
    end


    describe 'created span' do
      subject(:span) { tracer.writer.spans.first }
      before do
        request
      end

      it 'has tag with target host' do
        expect(span.get_tag(Datadog::Ext::NET::TARGET_HOST)).to eq(host)
      end

      it 'has tag with target port' do
        expect(span.get_tag(Datadog::Ext::NET::TARGET_PORT)).to eq('80')
      end

      it 'has tag with target port' do
        expect(span.get_tag(Datadog::Ext::HTTP::METHOD)).to eq('GET')
      end

      it 'has tag with target port' do
        expect(span.get_tag(Datadog::Ext::HTTP::URL)).to eq(path)
      end

      it 'is http type' do
        expect(span.span_type).to eq('http')
      end

      it 'is named correctly' do
        expect(span.name).to eq('rest_client.request')
      end
    end
  end
end
