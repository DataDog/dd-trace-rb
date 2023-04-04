require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/analytics_examples'
require 'datadog/tracing/contrib/integration_examples'
require 'datadog/tracing/contrib/environment_service_name_examples'

require 'ddtrace'

require 'elasticsearch'

require 'datadog/tracing/contrib/elasticsearch/support/client'

RSpec.describe Datadog::Tracing::Contrib::Elasticsearch::Patcher do
  include_context 'Elasticsearch client'

  let(:client) { Elasticsearch::Client.new(url: server, adapter: :net_http) }
  let(:configuration_options) { {} }

  before do
    Datadog.configure do |c|
      c.tracing.instrument :elasticsearch, configuration_options
    end
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
      expect { request }.to change { fetch_spans.first }.to Datadog::Tracing::Span
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

      it_behaves_like 'environment service name', 'DD_TRACE_ELASTICSEARCH_SERVICE_NAME'

      it { expect(span.name).to eq('elasticsearch.query') }
      it { expect(span.service).to eq('elasticsearch') }
      it { expect(span.resource).to eq('GET _cluster/health') }
      it { expect(span.span_type).to eq('elasticsearch') }
      it { expect(span.parent_id).not_to be_nil }
      it { expect(span.trace_id).not_to be_nil }

      it {
        expect(span.get_tag('db.system')).to eq('elasticsearch')
      }

      it {
        expect(span.get_tag('component')).to eq('elasticsearch')
      }

      it {
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_KIND)).to eq('client')
      }

      it {
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
          .to eq('query')
      }

      it_behaves_like 'a peer service span' do
        let(:peer_hostname) { host }
      end
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
    let(:document_id) { 1 }

    subject(:request) { client.perform_request 'PUT', "#{index_name}/_doc/#{document_id}", {}, document_body }

    it 'creates a span' do
      expect { request }.to change { fetch_spans.first }.to Datadog::Tracing::Span
    end

    describe 'index request span' do
      before { request }

      it_behaves_like 'analytics for integration' do
        let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Elasticsearch::Ext::ENV_ANALYTICS_ENABLED }
        let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Elasticsearch::Ext::ENV_ANALYTICS_SAMPLE_RATE }
      end

      it_behaves_like 'measured span for integration', false

      it_behaves_like 'environment service name', 'DD_TRACE_ELASTICSEARCH_SERVICE_NAME'

      it { expect(span.name).to eq('elasticsearch.query') }
      it { expect(span.service).to eq('elasticsearch') }
      it { expect(span.span_type).to eq('elasticsearch') }
      it { expect(span.resource).to eq('PUT some_index/_doc/?') }

      it { expect(span.parent_id).not_to be_nil }
      it { expect(span.trace_id).not_to be_nil }

      it {
        expect(span.get_tag('db.system')).to eq('elasticsearch')
      }

      it {
        expect(span.get_tag('component')).to eq('elasticsearch')
      }

      it {
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_KIND)).to eq('client')
      }

      it {
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
          .to eq('query')
      }

      it 'tags span with quantized request body' do
        expect(span.get_tag('elasticsearch.body'))
          .to eq('{"field":"?","nested_object":{"value":"?"},"nested_array":["?"],"nested_object_array":[{"a":"?"},"?"]}')
      end

      it_behaves_like 'a peer service span' do
        let(:peer_hostname) { host }
      end
    end
  end
end
