require 'helper'

require 'contrib/rails/test_helper'

class TracerTest < ActionController::TestCase
  setup do
    # don't pollute the global tracer
    @tracer = get_test_tracer
    Rails.configuration.datadog_trace[:tracer] = @tracer
  end

  teardown do
    # reset default configuration
    Datadog::Contrib::Rails::Framework.configure({})
  end

  def update_config(key, value)
    # update Datadog user configuration
    ::Rails.configuration.datadog_trace[key] = value
    config = { config: ::Rails.application.config }
    Datadog::Contrib::Rails::Framework.configure(config)
  end

  test 'the configuration is correctly called' do
    assert Rails.configuration.datadog_trace[:enabled]
    assert Rails.configuration.datadog_trace[:auto_instrument]
    assert_equal(Rails.configuration.datadog_trace[:default_service], 'rails-app')
    assert_equal(Rails.configuration.datadog_trace[:template_base_path], 'views/')
    assert Rails.configuration.datadog_trace[:tracer]
  end

  test 'a default service and database are properly set' do
    Datadog::Contrib::Rails::Framework.configure({})
    tracer = Rails.configuration.datadog_trace[:tracer]
    assert_equal(
      tracer.services,
      'rails-app' => {
        'app' => 'rails', 'app_type' => 'web'
      },
      'postgres' => {
        'app' => 'postgres', 'app_type' => 'db'
      }
    )
  end

  test 'database service can be changed by user' do
    update_config(:default_database_service, 'customer-db')
    tracer = Rails.configuration.datadog_trace[:tracer]

    assert_equal(
      tracer.services,
      'rails-app' => {
        'app' => 'rails', 'app_type' => 'web'
      },
      'customer-db' => {
        'app' => 'postgres', 'app_type' => 'db'
      }
    )
  end

  test 'application service can be changed by user' do
    update_config(:default_service, 'my-custom-app')
    tracer = Rails.configuration.datadog_trace[:tracer]

    assert_equal(
      tracer.services,
      'my-custom-app' => {
        'app' => 'rails', 'app_type' => 'web'
      },
      'postgres' => {
        'app' => 'postgres', 'app_type' => 'db'
      }
    )
  end
end
