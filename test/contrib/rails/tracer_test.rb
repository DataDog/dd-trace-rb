require 'helper'

require 'contrib/rails/test_helper'

# rubocop:disable Metrics/ClassLength
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
    assert !Datadog.configuration[:rails][:debug]
    assert_equal(Datadog.configuration[:rails][:trace_agent_hostname], Datadog::Writer::HOSTNAME)
    assert_equal(Datadog.configuration[:rails][:trace_agent_port], Datadog::Writer::PORT)
    assert_nil(Datadog.configuration[:rails][:env], 'no env should be set by default')
    assert_equal(Datadog.configuration[:rails][:tags], {}, 'no tags should be set by default')
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

  test 'debug logging can be changed by the user' do
    update_config(:debug, true)

    assert_equal(Datadog::Tracer.debug_logging, true)
  end

  test 'tracer agent address can be changed by the user' do
    update_config(:trace_agent_hostname, 'example.com')
    update_config(:trace_agent_port, 42)

    tracer = Datadog.configuration[:rails][:tracer]

    assert_equal(tracer.writer.transport.hostname, 'example.com')
    assert_equal(tracer.writer.transport.port, 42)
  end

  test 'tracer environment can be changed by the user' do
    update_config(:env, 'dev')

    tracer = Datadog.configuration[:rails][:tracer]

    assert_equal(tracer.tags['env'], 'dev')
  end

  test 'tracer global tags can be changed by the user' do
    update_config(:tags, 'component' => 'api', 'section' => 'users')

    tracer = Datadog.configuration[:rails][:tracer]

    assert_equal(tracer.tags['component'], 'api')
    assert_equal(tracer.tags['section'], 'users')
  end

  test 'tracer env and env tag setting precedence' do
    # default case
    tracer = Datadog.configuration[:rails][:tracer]
    assert_nil(tracer.tags['env'])

    # use the Rails value
    update_config(:env, ::Rails.env)
    update_config(:tags, 'env' => 'foo')
    tracer = Datadog.configuration[:rails][:tracer]
    assert_equal(tracer.tags['env'], 'test')

    # explicit set
    update_config(:env, 'dev')
    update_config(:tags, 'env' => 'bar')
    tracer = Datadog.configuration[:rails][:tracer]
    assert_equal(tracer.tags['env'], 'dev')

    # env is not valid but tags is set
    update_config(:env, nil)
    update_config(:tags, 'env' => 'bar')
    tracer = Datadog.configuration[:rails][:tracer]
    assert_equal(tracer.tags['env'], 'bar')
  end
end
