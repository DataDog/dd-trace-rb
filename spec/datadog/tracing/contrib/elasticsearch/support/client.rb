RSpec.shared_context 'Elasticsearch client' do
  let(:host) { ENV.fetch('TEST_ELASTICSEARCH_HOST', '127.0.0.1') }
  let(:port) { ENV.fetch('TEST_ELASTICSEARCH_PORT', '9200').to_i }
  let(:server) { "http://#{host}:#{port}" }

  before do
    wait_http_server(server, 60)

    # Elasticsearch sends a sanity request to `/` once per client.
    # We send a preemptive request here to avoid polluting our test runs with
    # this verification request.
    # @see https://github.com/elastic/elasticsearch-ruby/blob/ce84322759ff494764bbd096922faff998342197/elasticsearch/lib/elasticsearch.rb#L161
    client.perform_request('GET', '/')
    clear_traces!
  end
end
