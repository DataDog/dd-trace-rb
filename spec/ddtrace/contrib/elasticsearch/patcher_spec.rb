require 'spec_helper'
require 'ddtrace'
require 'elasticsearch'

ELASTICSEARCH_HOST = ENV.fetch('TEST_ELASTICSEARCH_HOST', '127.0.0.1').freeze
ELASTICSEARCH_PORT = ENV.fetch('TEST_ELASTICSEARCH_PORT', '9200').freeze
ELASTICSEARCH_SERVER = "http://#{ELASTICSEARCH_HOST}:#{ELASTICSEARCH_PORT}".freeze

RSpec.describe Datadog::Contrib::Elasticsearch::Patcher do
  let(:client) { Elasticsearch::Client.new(url: ELASTICSEARCH_SERVER) }
  let(:pin) { Datadog::Pin.get_from(client) }
  let(:tracer) { Datadog::Tracer.new(writer: FauxWriter.new) }

  before do
    Datadog.configure do |c|
      c.use :elasticsearch
    end

    wait_http_server(ELASTICSEARCH_SERVER, 60)
    pin.tracer = tracer
  end

  describe 'cluster health request' do
    subject(:request) { client.cluster.health }

    it 'creates a span' do
      expect { request }.to change { tracer.writer.spans.first }.to Datadog::Span
    end

    describe 'health request span' do
      before { request }

      subject(:span) { tracer.writer.spans.first }

      it { expect(span.name).to eq('elasticsearch.query') }
      it { expect(span.service).to eq('elasticsearch') }
      it { expect(span.resource).to eq('GET _cluster/health') }
      it { expect(span.parent_id).not_to be_nil }
      it { expect(span.trace_id).not_to be_nil }
    end

    describe 'health request span' do
      before do
        request
      end

      subject(:span) { tracer.writer.spans.first }

      it { expect(span.name).to eq('elasticsearch.query') }
      it { expect(span.service).to eq('elasticsearch') }
      it { expect(span.resource).to eq('GET _cluster/health') }
      it { expect(span.parent_id).not_to be_nil }
      it { expect(span.trace_id).not_to be_nil }
    end
  end

  describe 'indexing request' do
    let(:document_body) do
      {
        field: 'Test',
        nested_object: {
          value: 'x'
        },
        nested_array: %w[a b],
        nested_object_array: [
          { a: 'a' },
          { b: 'b' }
        ]
      }
    end
    let(:index_name) { 'some_index' }
    let(:document_type) { 'type' }
    let(:document_id) { 1 }

    subject(:request) { client.index index: index_name, type: document_type, id: document_id, body: document_body }

    it 'creates a span' do
      expect { request }.to change { tracer.writer.spans.first }.to Datadog::Span
    end

    describe 'index request span' do
      before { request }
      subject(:span) { tracer.writer.spans.first }

      it { expect(span.name).to eq('elasticsearch.query') }
      it { expect(span.service).to eq('elasticsearch') }
      it { expect(span.resource).to eq('PUT some_index/type/?') }

      it { expect(span.parent_id).not_to be_nil }
      it { expect(span.trace_id).not_to be_nil }

      it 'tags span with quantized request body' do
        expect(span.get_tag('elasticsearch.body'))
          .to eq('{"field":"?","nested_object":{"value":"?"},"nested_array":["?"],"nested_object_array":[{"a":"?"},"?"]}')
      end
    end
  end
end
