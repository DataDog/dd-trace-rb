require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/integration_examples'
require 'datadog/tracing/contrib/span_attribute_schema_examples'
require 'datadog/tracing/contrib/environment_service_name_examples'
require 'datadog/tracing/contrib/peer_service_configuration_examples'

require 'datadog'

require 'opensearch'

require 'datadog/tracing/contrib/opensearch/integration'

RSpec.describe 'OpenSearch instrumentation' do
  let(:configuration_options) { {} }
  let(:base_url) { "http://#{host}:#{port}" }
  let(:host) { ENV.fetch('TEST_OPENSEARCH_HOST', '127.0.0.1') }
  let(:port) { ENV.fetch('TEST_OPENSEARCH_PORT', '9200').to_i }
  let(:client) do
    OpenSearch::Client.new(
      host: base_url,
      user: 'admin',
      password: 'admin',
      transport_options: { ssl: { verify: false } } # For testing only. Use certificate for validation.
    )
  end
  let(:index_name) { 'ruby-test-index' }
  let(:index_body) do
    {
      settings: {
        index: {
          number_of_shards: 4
        }
      }
    }
  end
  let(:id) { '1' }
  let(:document) do
    {
      title: 'Moneyball',
      director: 'Bennett Miller',
      year: '2011'
    }
  end

  before do
    Datadog.configure do |c|
      c.tracing.instrument :opensearch, configuration_options
    end

    # Create a client index before every test case
    unless client.indices.exists?(index: index_name)
      client.indices.create(
        index: index_name,
        body: index_body
      )
    end

    # Remove spans created during set up so that test runs have a clean set of spans to assert on
    clear_traces!
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:opensearch].reset_configuration!
    example.run
    Datadog.registry[:opensearch].reset_configuration!
  end

  # Deletes index after each test case has run
  after do
    if client.indices.exists?(index: index_name)
      client.indices.delete(
        index: index_name
      )
    end
  end

  context 'deleting an index' do
    subject(:delete_indices) do
      client.indices.delete(
        index: index_name
      )
    end

    it_behaves_like 'environment service name', 'DD_TRACE_OPENSEARCH_SERVICE_NAME'
    it_behaves_like 'configured peer service span', 'DD_TRACE_OPENSEARCH_PEER_SERVICE'

    it_behaves_like 'a peer service span' do
      let(:peer_service_val) { ENV.fetch('TEST_OPENSEARCH_HOST', '127.0.0.1') }
      let(:peer_service_source) { 'peer.hostname' }
    end

    it_behaves_like 'schema version span'

    it 'sets the correct span tags and resource' do
      delete_indices

      expect(span.get_tag('http.method')).to eq('DELETE')
      expect(span.get_tag('http.url_details.path')).to eq('ruby-test-index')
      expect(span.get_metric('http.response.content_length')).to be_a(Float)
      expect(span.resource).to eq("DELETE #{base_url}/ruby-test-index")
    end
  end

  context 'creating an index' do
    before do
      client.indices.delete(
        index: index_name
      )

      clear_traces!
    end

    subject(:create_indices) do
      client.indices.create(
        index: index_name,
        body: index_body
      )
    end

    it_behaves_like 'environment service name', 'DD_TRACE_OPENSEARCH_SERVICE_NAME'
    it_behaves_like 'configured peer service span', 'DD_TRACE_OPENSEARCH_PEER_SERVICE'

    it_behaves_like 'a peer service span' do
      let(:peer_service_val) { ENV.fetch('TEST_OPENSEARCH_HOST', '127.0.0.1') }
      let(:peer_service_source) { 'peer.hostname' }
    end

    it_behaves_like 'schema version span'

    it 'sets the correct span tags and resource' do
      create_indices

      expect(span.get_tag('component')).to eq('opensearch')
      expect(span.get_tag('span.kind')).to eq('client')
      expect(span.get_tag('db.system')).to eq('opensearch')
      expect(span.get_tag('http.method')).to eq('PUT')
      expect(span.get_tag('http.url_details.path')).to eq('ruby-test-index')
      expect(span.get_tag('opensearch.params')).to eq('{}')
      expect(span.get_tag('opensearch.body')).to eq('{"settings":{"index":{"number_of_shards":"?"}}}')
      expect(span.get_tag('http.url')).to eq("#{base_url}/ruby-test-index")
      expect(span.get_tag('http.url_details.host')).to eq(host)
      expect(span.get_tag('http.url_details.scheme')).to eq('http')
      expect(span.get_tag('http.status_code')).to eq('200')
      expect(span.get_metric('http.url_details.port')).to eq(port)
      expect(span.get_metric('http.response.content_length')).to be_a(Float)
      expect(span.name).to eq('opensearch.query')
      expect(span.resource).to eq("PUT #{base_url}/ruby-test-index")
      expect(span.service).to eq('opensearch')
    end
  end

  context 'adding a document to the index' do
    subject(:index) do
      client.index(
        index: index_name,
        body: document,
        id: id,
        refresh: true
      )
    end

    it_behaves_like 'environment service name', 'DD_TRACE_OPENSEARCH_SERVICE_NAME'
    it_behaves_like 'configured peer service span', 'DD_TRACE_OPENSEARCH_PEER_SERVICE'

    it_behaves_like 'a peer service span' do
      let(:peer_service_val) { ENV.fetch('TEST_OPENSEARCH_HOST', '127.0.0.1') }
      let(:peer_service_source) { 'peer.hostname' }
    end

    it_behaves_like 'schema version span'

    it 'sets the correct span tags and resource' do
      index

      expect(span.get_tag('http.method')).to eq('PUT')
      expect(span.get_tag('http.url_details.path')).to eq('ruby-test-index/_doc/1')
      expect(span.get_tag('opensearch.body')).to eq('{"title":"?","director":"?","year":"?"}')
      expect(span.get_tag('opensearch.params')).to eq('{"refresh":true}')
      expect(span.get_metric('http.response.content_length')).to be_a(Float)
      expect(span.resource).to eq("PUT #{base_url}/ruby-test-index/_doc/?")
    end
  end

  context 'searching for query in index' do
    before do
      client.index(
        index: index_name,
        body: document,
        id: id,
        refresh: true
      )

      clear_traces!
    end

    let(:q) { 'miller' }

    let(:query) do
      {
        size: 5,
        query: {
          multi_match: {
            query: q,
            fields: ['title^2', 'director']
          }
        }
      }
    end

    subject(:search) do
      client.search(
        body: query,
        index: index_name
      )
    end

    it_behaves_like 'environment service name', 'DD_TRACE_OPENSEARCH_SERVICE_NAME'
    it_behaves_like 'configured peer service span', 'DD_TRACE_OPENSEARCH_PEER_SERVICE'

    it_behaves_like 'a peer service span' do
      let(:peer_service_val) { ENV.fetch('TEST_OPENSEARCH_HOST', '127.0.0.1') }
      let(:peer_service_source) { 'peer.hostname' }
    end

    it_behaves_like 'schema version span'

    it 'sets the correct span tags and resource' do
      search

      expect(span.get_tag('http.method')).to eq('POST')
      expect(span.get_tag('http.url_details.path')).to eq('ruby-test-index/_search')
      expect(span.get_tag('opensearch.body')).to eq('{"size":"?","query":{"multi_match":{"query":"?","fields":["?"]}}}')
      expect(span.get_metric('http.response.content_length')).to be_a(Float)
      expect(span.resource).to eq("POST #{base_url}/ruby-test-index/_search")
    end
  end

  context 'deleting indexed document' do
    before do
      client.index(
        index: index_name,
        body: document,
        id: id,
        refresh: true
      )

      clear_traces!
    end

    subject(:delete) do
      client.delete(
        index: index_name,
        id: id
      )
    end

    it_behaves_like 'environment service name', 'DD_TRACE_OPENSEARCH_SERVICE_NAME'
    it_behaves_like 'configured peer service span', 'DD_TRACE_OPENSEARCH_PEER_SERVICE'

    it_behaves_like 'a peer service span' do
      let(:peer_service_val) { ENV.fetch('TEST_OPENSEARCH_HOST', '127.0.0.1') }
      let(:peer_service_source) { 'peer.hostname' }
    end

    it_behaves_like 'schema version span'

    it 'sets the correct span tags and resource' do
      delete

      expect(span.get_tag('http.method')).to eq('DELETE')
      expect(span.get_tag('http.url_details.path')).to eq('ruby-test-index/_doc/1')
      expect(span.get_metric('http.response.content_length')).to be_a(Float)
      expect(span.resource).to eq("DELETE #{base_url}/ruby-test-index/_doc/?")
    end
  end

  context 'when opensearch client throws an error' do
    subject(:test_error) do
      client.indices.create(
        index: index_name,
        body: index_body
      )
    end

    it 'sets the correct span tags and resource. marks the span with an error' do
      expect { test_error }.to raise_error(OpenSearch::Transport::Transport::Errors::BadRequest)

      expect(span).to have_error
      expect(span).to have_error_message(include('resource_already_exists_exception'))
      expect(span).to have_error_type('OpenSearch::Transport::Transport::Errors::BadRequest')
      expect(span).to have_error_stack(include('patcher.rb'))

      expect(span.get_tag('component')).to eq('opensearch')
      expect(span.get_tag('span.kind')).to eq('client')
      expect(span.get_tag('db.system')).to eq('opensearch')
      expect(span.get_tag('http.method')).to eq('PUT')
      expect(span.get_tag('http.url_details.path')).to eq('ruby-test-index')
      expect(span.get_tag('opensearch.params')).to eq('{}')
      expect(span.get_tag('opensearch.body')).to eq('{"settings":{"index":{"number_of_shards":"?"}}}')
      expect(span.get_tag('http.url')).to eq("#{base_url}/ruby-test-index")
      expect(span.get_tag('http.url_details.host')).to eq(host)
      expect(span.get_tag('http.url_details.scheme')).to eq('http')
      expect(span.get_tag('http.status_code')).to eq('400')
      expect(span.get_metric('http.url_details.port')).to eq(port)
      expect(span.name).to eq('opensearch.query')
      expect(span.resource).to eq("PUT #{base_url}/ruby-test-index")
      expect(span.service).to eq('opensearch')
    end
  end
end
