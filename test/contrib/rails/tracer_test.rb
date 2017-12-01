require 'helper'

require 'contrib/rails/test_helper'

class TracerTest < ActionDispatch::IntegrationTest
  setup do
    # don't pollute the global tracer
    @tracer = get_test_tracer
    @config = Datadog.configuration[:rails]
    Datadog.registry[:rails].reset_options!
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

  test 'a default service and database should be properly set' do
    services = Datadog.configuration[:rails][:tracer].services
    Datadog::Contrib::Rails::Framework.setup
    adapter_name = get_adapter_name()
    assert_equal(
      {
        app_name => {
          'app' => 'rails', 'app_type' => 'web'
        },
        "#{app_name}-#{adapter_name}" => {
          'app' => adapter_name, 'app_type' => 'db'
        },
        "#{app_name}-cache" => {
          'app' => 'rails', 'app_type' => 'cache'
        }
      },
      services
    )
  end

  test 'database service can be changed by user' do
    update_config(:database_service, 'customer-db')
    tracer = Datadog.configuration[:rails][:tracer]
    adapter_name = get_adapter_name()

    assert_equal(
      {
        app_name => {
          'app' => 'rails', 'app_type' => 'web'
        },
        'customer-db' => {
          'app' => adapter_name, 'app_type' => 'db'
        },
        "#{app_name}-cache" => {
          'app' => 'rails', 'app_type' => 'cache'
        }
      },
      tracer.services
    )
  end

  test 'application service can be changed by user' do
    tracer = Datadog.configuration[:rails][:tracer]
    update_config(:controller_service, 'my-custom-app')
    adapter_name = get_adapter_name()

    assert_equal(
      {
        app_name => {
          'app' => 'rack', 'app_type' => 'web'
        },
        'my-custom-app' => {
          'app' => 'rails', 'app_type' => 'web'
        },
        "#{app_name}-#{adapter_name}" => {
          'app' => adapter_name, 'app_type' => 'db'
        },
        "#{app_name}-cache" => {
          'app' => 'rails', 'app_type' => 'cache'
        }
      },
      tracer.services
    )
  end

  test 'cache service can be changed by user' do
    update_config(:cache_service, 'service-cache')
    tracer = Datadog.configuration[:rails][:tracer]
    adapter_name = get_adapter_name()

    assert_equal(
      {
        app_name => {
          'app' => 'rails', 'app_type' => 'web'
        },
        "#{app_name}-#{adapter_name}" => {
          'app' => adapter_name, 'app_type' => 'db'
        },
        'service-cache' => {
          'app' => 'rails', 'app_type' => 'cache'
        }
      },
      tracer.services
    )
  end
end
