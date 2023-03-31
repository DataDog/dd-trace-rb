RSpec.shared_context 'Opensearch client' do
  let(:host) { ENV.fetch('TEST_OPENSEARCH_HOST', '127.0.0.1') }
  let(:port) { ENV.fetch('TEST_OPENSEARCH_PORT', '9200').to_i }
  let(:server) { "http://#{host}:#{port}" }

  before do
    wait_http_server(server, 60)

    # Opensearch sends a sanity request to `/` once per client.
    # We send a preemptive request here to avoid polluting our test runs with
    # this verification request.
    # @see https://github.com/opensearch-project/opensearch-ruby/blob/main/opensearch-ruby/lib/opensearch.rb#L91
    client.perform_request('GET', '/')
    clear_traces!
  end
end
