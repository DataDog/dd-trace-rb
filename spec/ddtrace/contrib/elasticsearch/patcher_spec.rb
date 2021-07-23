require 'ddtrace/contrib/support/spec_helper'
require 'ddtrace/contrib/analytics_examples'
require 'ddtrace/contrib/integration_examples'

require 'ddtrace'
require 'elasticsearch-transport'

RSpec.describe Datadog::Contrib::Elasticsearch::Patcher do
  let(:host) { ENV.fetch('TEST_ELASTICSEARCH_HOST', '127.0.0.1') }
  let(:port) { ENV.fetch('TEST_ELASTICSEARCH_PORT', '9200').to_i }
  let(:server) { "http://#{host}:#{port}" }

  let(:client) { Elasticsearch::Client.new(url: server, adapter: :net_http) }
  let(:configuration_options) { {} }

  before do
    Datadog.configure do |c|
      c.use :elasticsearch, configuration_options
    end

    wait_http_server(server, 60)
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:elasticsearch].reset_configuration!
    example.run
    Datadog.registry[:elasticsearch].reset_configuration!
  end

  describe 'cluster health request' do
    subject(:request) { client.perform_request 'GET', '_cluster/health' }

    it 'creates a span' do
      expect { request }.to change { fetch_spans.first }.to Datadog::Span
    end

    context 'inside a span' do
      subject(:request_inside_a_span) do
        tracer.trace('publish') do |span|
          span.service = 'webapp'
          span.resource = '/status'
          request
        end
      end

      it 'creates a child request span' do
        expect { request_inside_a_span }.to change { fetch_spans.length }.to 2
      end

      it 'sets request span parent id and trace id' do
        request_inside_a_span

        child, parent = spans

        expect(child.parent_id).to eq(parent.span_id)
        expect(child.trace_id).to eq(parent.trace_id)
      end
    end

    describe 'health request span' do
      before { request }

      it { expect(span.name).to eq('elasticsearch.query') }
      it { expect(span.service).to eq('elasticsearch') }
      it { expect(span.resource).to eq('GET _cluster/health') }
      it { expect(span.span_type).to eq('elasticsearch') }
      it { expect(span.parent_id).not_to be_nil }
      it { expect(span.trace_id).not_to be_nil }

      it_behaves_like 'a peer service span'
    end

    describe 'health request span' do
      before do
        request
      end

      it { expect(span.name).to eq('elasticsearch.query') }
      it { expect(span.service).to eq('elasticsearch') }
      it { expect(span.resource).to eq('GET _cluster/health') }
      it { expect(span.span_type).to eq('elasticsearch') }
      it { expect(span.parent_id).not_to be_nil }
      it { expect(span.trace_id).not_to be_nil }

      it_behaves_like 'a peer service span'
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

    subject(:request) { client.perform_request 'PUT', "#{index_name}/#{document_type}/#{document_id}", {}, document_body }

    it 'creates a span' do
      expect { request }.to change { fetch_spans.first }.to Datadog::Span
    end

    describe 'index request span' do
      before { request }

      it_behaves_like 'analytics for integration' do
        let(:analytics_enabled_var) { Datadog::Contrib::Elasticsearch::Ext::ENV_ANALYTICS_ENABLED }
        let(:analytics_sample_rate_var) { Datadog::Contrib::Elasticsearch::Ext::ENV_ANALYTICS_SAMPLE_RATE }
      end

      it_behaves_like 'measured span for integration', false

      it { expect(span.name).to eq('elasticsearch.query') }
      it { expect(span.service).to eq('elasticsearch') }
      it { expect(span.span_type).to eq('elasticsearch') }
      it { expect(span.resource).to eq('PUT some_index/type/?') }

      it { expect(span.parent_id).not_to be_nil }
      it { expect(span.trace_id).not_to be_nil }

      it 'tags span with quantized request body' do
        expect(span.get_tag('elasticsearch.body'))
          .to eq('{"field":"?","nested_object":{"value":"?"},"nested_array":["?"],"nested_object_array":[{"a":"?"},"?"]}')
      end

      it_behaves_like 'a peer service span'
    end
  end
end
