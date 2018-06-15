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

  describe 'instrumented request' do
    let(:path) { '/sample/path' }
    let(:host) { 'example.com' }
    let(:url) { "http://#{host}#{path}" }
    let(:status) { 200 }
    let(:response) { 'response' }

    subject(:request) { RestClient.get(url) }

    before do
      stub_request(:get, url)
        .to_return(status: status, body: response)
    end

    it 'creates a span' do
      expect { request }.to change { tracer.writer.spans.first }.to be_instance_of(Datadog::Span)
    end

    it 'returns response' do
      expect(request.body).to eq(response)
    end

    describe 'created span' do
      subject(:span) { tracer.writer.spans.first }

      context 'response is successfull' do
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

        it 'has tag with status code' do
          expect(span.get_tag(Datadog::Ext::HTTP::STATUS_CODE)).to eq(status.to_s)
        end

        it 'is http type' do
          expect(span.span_type).to eq('http')
        end

        it 'is named correctly' do
          expect(span.name).to eq('rest_client.request')
        end
      end

      context 'response has internal server error status' do
        let(:status) { 500 }

        before do
          expect { request }.to raise_exception(RestClient::InternalServerError)
        end

        it 'has tag with status code' do
          expect(span.get_tag(Datadog::Ext::HTTP::STATUS_CODE)).to eq(status.to_s)
        end

        it 'has error set' do
          expect(span.get_tag(Datadog::Ext::Errors::MSG)).to eq('500 Internal Server Error')
        end
        it 'has error stack' do
          expect(span.get_tag(Datadog::Ext::Errors::STACK)).not_to be_nil
        end
        it 'has error set' do
          expect(span.get_tag(Datadog::Ext::Errors::TYPE)).to eq('RestClient::InternalServerError')
        end
      end

      context 'response has not found status' do
        let(:status) { 404 }

        before do
          expect { request }.to raise_exception(RestClient::NotFound)
        end

        it 'has tag with status code' do
          expect(span.get_tag(Datadog::Ext::HTTP::STATUS_CODE)).to eq(status.to_s)
        end

        it 'error is not set' do
          expect(span.get_tag(Datadog::Ext::Errors::MSG)).to be_nil
        end
      end
    end
  end
end
