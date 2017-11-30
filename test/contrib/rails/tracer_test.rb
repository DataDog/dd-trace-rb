require 'helper'

require 'contrib/rails/test_helper'

class TracerTest < ActionDispatch::IntegrationTest
  setup do
    # don't pollute the global tracer
    @tracer = get_test_tracer
    Datadog.registry[:rails].reset_options!
    Datadog.configuration[:rails][:database_service] = get_adapter_name
    Datadog.configuration[:rails][:tracer] = @tracer
  end

  teardown do
    reset_config()
  end

  test 'the configuration is correctly called' do
    assert Datadog.configuration[:rails][:enabled]
    assert_equal(Datadog.configuration[:rails][:service_name], 'rails-app')
    assert_equal(Datadog.configuration[:rails][:controller_service], 'rails-controller')
    assert_equal(Datadog.configuration[:rails][:cache_service], 'rails-cache')
    refute_nil(Datadog.configuration[:rails][:database_service])
    assert_equal(Datadog.configuration[:rails][:template_base_path], 'views/')
    assert Datadog.configuration[:rails][:tracer]
  end

  test 'a default service and database should be properly set' do
    update_config(:cache_service, 'rails-cache')
    reset_config()
    services = Datadog.configuration[:rails][:tracer].services
    adapter_name = get_adapter_name()
    assert_equal(
      services,
      'rails-app' => {
        'app' => 'rack', 'app_type' => 'web'
      },
      'rails-controller' => {
        'app' => 'rails', 'app_type' => 'web'
      },
      adapter_name => {
        'app' => adapter_name, 'app_type' => 'db'
      },
      'rails-cache' => {
        'app' => 'rails', 'app_type' => 'cache'
      }
    )
  end

  test 'database service can be changed by user' do
    update_config(:database_service, 'customer-db')
    tracer = Datadog.configuration[:rails][:tracer]
    adapter_name = get_adapter_name()

    assert_equal(
      tracer.services,
      'rails-app' => {
        'app' => 'rack', 'app_type' => 'web'
      },
      'rails-controller' => {
        'app' => 'rails', 'app_type' => 'web'
      },
      'customer-db' => {
        'app' => adapter_name, 'app_type' => 'db'
      },
      'rails-cache' => {
        'app' => 'rails', 'app_type' => 'cache'
      }
    )
  end

  test 'application service can be changed by user' do
    update_config(:controller_service, 'my-custom-app')
    tracer = Datadog.configuration[:rails][:tracer]
    adapter_name = get_adapter_name()

    assert_equal(
      tracer.services,
      'rails-app' => {
        'app' => 'rack', 'app_type' => 'web'
      },
      'my-custom-app' => {
        'app' => 'rails', 'app_type' => 'web'
      },
      adapter_name => {
        'app' => adapter_name, 'app_type' => 'db'
      },
      'rails-cache' => {
        'app' => 'rails', 'app_type' => 'cache'
      }
    )
  end

  test 'cache service can be changed by user' do
    update_config(:cache_service, 'service-cache')
    tracer = Datadog.configuration[:rails][:tracer]
    adapter_name = get_adapter_name()

    assert_equal(
      tracer.services,
      'rails-app' => {
        'app' => 'rack', 'app_type' => 'web'
      },
      'rails-controller' => {
        'app' => 'rails', 'app_type' => 'web'
      },
      adapter_name => {
        'app' => adapter_name, 'app_type' => 'db'
      },
      'service-cache' => {
        'app' => 'rails', 'app_type' => 'cache'
      }
    )
  end
end
