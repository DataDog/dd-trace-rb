require 'helper'

require 'contrib/rails/test_helper'

class TracerTest < ActionDispatch::IntegrationTest
  setup do
    # don't pollute the global tracer
    @tracer = get_test_tracer
    @config = Datadog.configuration[:rails]
    Datadog.configuration[:rails].reset!
    @config[:tracer] = @tracer
  end

  teardown do
    reset_config()
  end

  test 'the configuration is correctly called' do
    Datadog::Contrib::Rails::Framework.setup
    assert_equal(app_name, @config[:service_name])
    assert_equal(@config[:service_name], @config[:controller_service])
    assert_equal("#{app_name}-cache", @config[:cache_service])
    refute_nil(Datadog.configuration[:rails][:database_service])
    assert_equal('views/', @config[:template_base_path])
    assert Datadog.configuration[:rails][:tracer]
  end

  test 'a default database should be properly set' do
    Datadog::Contrib::Rails::Framework.setup
    adapter_name = get_adapter_name
    refute_equal(adapter_name, 'defaultdb')
  end
end
