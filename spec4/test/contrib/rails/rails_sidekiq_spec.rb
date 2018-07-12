require('helper')
require('sidekiq/testing')
require('contrib/rails/test_helper')
require('ddtrace/contrib/sidekiq/tracer')
RSpec.describe(RailsSidekiq) do
  before do
    @original_tracer = Datadog.configuration[:rails][:tracer]
    @tracer = get_test_tracer
    Datadog.configuration[:rails][:tracer] = @tracer
    Sidekiq.configure_client do |config|
      config.redis = { url: ENV['REDIS_URL'] }
    end
    Sidekiq.configure_server do |config|
      config.redis = { url: ENV['REDIS_URL'] }
    end
    Sidekiq::Testing.inline!
  end
  after { Datadog.configuration[:rails][:tracer] = @original_tracer }
  class EmptyWorker
    include(Sidekiq::Worker)
    def perform
      # do nothing
    end
  end
  it('Sidekiq middleware uses Rails configuration if available') do
    @tracer.configure(enabled: false, debug: true, host: 'tracer.example.com', port: 7777)
    Datadog::Contrib::Rails::Framework.setup
    db_adapter = get_adapter_name
    Sidekiq::Testing.server_middleware do |chain|
      chain.add(Datadog::Contrib::Sidekiq::Tracer, tracer: @tracer, service_name: 'rails-sidekiq')
    end
    EmptyWorker.perform_async
    expect(app_name => { 'app' => 'rails', 'app_type' => 'web' },
           "#{app_name}-#{db_adapter}" => { 'app' => 'active_record', 'app_type' => 'db' },
           "#{app_name}-cache" => { 'app' => 'rails', 'app_type' => 'cache' },
           'rails-sidekiq' => { 'app' => 'sidekiq', 'app_type' => 'worker' })
      .to(eq(@tracer.services))
  end
end
