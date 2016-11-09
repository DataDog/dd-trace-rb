require 'helper'

require 'contrib/rails/test_helper'

class TracerTest < ActionController::TestCase
  setup do
    # don't pollute the global tracer
    @tracer = get_test_tracer
    Rails.configuration.datadog_trace[:tracer] = @tracer
  end

  teardown do
    reset_config()
  end

  test 'the configuration is correctly called' do
    assert Rails.configuration.datadog_trace[:enabled]
    assert Rails.configuration.datadog_trace[:auto_instrument]
    assert_equal(Rails.configuration.datadog_trace[:default_service], 'rails-app')
    assert_equal(Rails.configuration.datadog_trace[:template_base_path], 'views/')
    assert Rails.configuration.datadog_trace[:tracer]
  end

  test 'a default service and database should be properly set' do
    tracer = Datadog.tracer
    adapter_name = get_adapter_name()
    assert_equal(
      tracer.services,
      'rails-app' => {
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
    update_config(:default_database_service, 'customer-db')
    tracer = Rails.configuration.datadog_trace[:tracer]
    adapter_name = get_adapter_name()

    assert_equal(
      tracer.services,
      'rails-app' => {
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
    update_config(:default_service, 'my-custom-app')
    tracer = Rails.configuration.datadog_trace[:tracer]
    adapter_name = get_adapter_name()

    assert_equal(
      tracer.services,
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
    update_config(:default_cache_service, 'service-cache')
    tracer = Rails.configuration.datadog_trace[:tracer]
    adapter_name = get_adapter_name()

    assert_equal(
      tracer.services,
      'rails-app' => {
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
