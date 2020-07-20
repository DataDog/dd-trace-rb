require 'sidekiq/testing'
require 'ddtrace'
require 'ddtrace/contrib/sidekiq/client_tracer'
require 'ddtrace/contrib/sidekiq/server_tracer'

RSpec.shared_context 'Sidekiq testing' do
  let(:redis_host) { ENV.fetch('TEST_REDIS_HOST', '127.0.0.1') }
  let(:redis_port) { ENV.fetch('TEST_REDIS_PORT', 6379) }

  before do
    Datadog.configure do |c|
      c.use :sidekiq
    end

    redis_url = "redis://#{redis_host}:#{redis_port}"

    Sidekiq.configure_client do |config|
      config.redis = { url: redis_url }
    end

    Sidekiq.configure_server do |config|
      config.redis = { url: redis_url }
    end

    Sidekiq::Testing.inline!
  end

  let!(:empty_worker) do
    stub_const('EmptyWorker', Class.new do
      include Sidekiq::Worker
      def perform; end
    end)
  end
end
