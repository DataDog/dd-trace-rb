require 'spec_helper'
require 'ddtrace'
require 'elasticsearch-transport'

RSpec.describe 'Elasticsearch integration tests' do
  let(:host) { ENV.fetch('TEST_ELASTICSEARCH_HOST', '127.0.0.1') }
  let(:port) { ENV.fetch('TEST_ELASTICSEARCH_PORT', '9200').to_i }
  let(:server) { "http://#{host}:#{port}" }

  let(:client) { Elasticsearch::Client.new(url: server) }
  let(:tracer) { Datadog.tracer }

  before(:each) do
    Datadog.configure do |c|
      c.tracer hostname: ENV.fetch('TEST_DDAGENT_HOST', 'localhost')
      c.use :elasticsearch
    end

    wait_http_server(server, 60)
  end

  describe 'when a request is made' do
    subject(:response) do
      client.perform_request('GET', '_cluster/health').tap do |resp|
        expect(resp.status).to eq(200)
        try_wait_until(attempts: 20) { tracer.writer.stats[:traces_flushed] >= already_flushed + 1 }
      end
    end

    let!(:already_flushed) { tracer.writer.stats[:traces_flushed] }

    it 'flushes a trace' do
      expect { response }.to change { tracer.writer.stats[:traces_flushed] }.by(1)
    end
  end
end
