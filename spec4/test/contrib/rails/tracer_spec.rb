require('helper')
require('contrib/rails/test_helper')
class TracerTest < ActionDispatch::IntegrationTest
  before do
    @tracer = get_test_tracer
    @config = Datadog.configuration[:rails]
    Datadog.registry[:rails].reset_options!
    @config[:tracer] = @tracer
  end
  after { reset_config }
  it('the configuration is correctly called') do
    Datadog::Contrib::Rails::Framework.setup
    expect(@config[:service_name]).to(eq(app_name))
    expect(@config[:controller_service]).to(eq(@config[:service_name]))
    expect(@config[:cache_service]).to(eq("#{app_name}-cache"))
    refute_nil(Datadog.configuration[:rails][:database_service])
    expect(@config[:template_base_path]).to(eq('views/'))
    expect(Datadog.configuration[:rails][:tracer]).to(be_truthy)
  end
  it('a default service and database should be properly set') do
    services = Datadog.configuration[:rails][:tracer].services
    Datadog::Contrib::Rails::Framework.setup
    adapter_name = get_adapter_name
    expect('defaultdb').to_not(eq(adapter_name))
    expect(services).to(eq(app_name => { 'app' => 'rails', 'app_type' => 'web' },
                           "#{app_name}-#{adapter_name}" => { 'app' => 'active_record', 'app_type' => 'db' },
                           "#{app_name}-cache" => { 'app' => 'rails', 'app_type' => 'cache' }))
  end
  it('database service can be changed by user') do
    update_config(:database_service, 'customer-db')
    tracer = Datadog.configuration[:rails][:tracer]
    expect(tracer.services).to(eq(app_name => { 'app' => 'rails', 'app_type' => 'web' },
                                  'customer-db' => { 'app' => 'active_record', 'app_type' => 'db' },
                                  "#{app_name}-cache" => { 'app' => 'rails', 'app_type' => 'cache' }))
  end
  it('application service can be changed by user') do
    tracer = Datadog.configuration[:rails][:tracer]
    update_config(:controller_service, 'my-custom-app')
    adapter_name = get_adapter_name
    expect(tracer.services).to(eq(app_name => { 'app' => 'rack', 'app_type' => 'web' },
                                  'my-custom-app' => { 'app' => 'rails', 'app_type' => 'web' },
                                  "#{app_name}-#{adapter_name}" => { 'app' => 'active_record', 'app_type' => 'db' },
                                  "#{app_name}-cache" => { 'app' => 'rails', 'app_type' => 'cache' }))
  end
  it('cache service can be changed by user') do
    update_config(:cache_service, 'service-cache')
    tracer = Datadog.configuration[:rails][:tracer]
    adapter_name = get_adapter_name
    expect(tracer.services).to(eq(app_name => { 'app' => 'rails', 'app_type' => 'web' },
                                  "#{app_name}-#{adapter_name}" => { 'app' => 'active_record', 'app_type' => 'db' },
                                  'service-cache' => { 'app' => 'rails', 'app_type' => 'cache' }))
  end
end
