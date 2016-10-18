require 'helper'

require 'contrib/rails/test_helper'

class TracerTest < ActionController::TestCase
  test 'the configuration is correctly called' do
    assert Rails.configuration.datadog_trace[:enabled]
    assert Rails.configuration.datadog_trace[:auto_instrument]
    assert_equal(Rails.configuration.datadog_trace[:default_service], 'rails-app')
    assert_equal(Rails.configuration.datadog_trace[:template_base_path], 'views/')
    assert_equal(Rails.configuration.datadog_trace[:tracer], Datadog.tracer)
  end

  test 'a default service is properly set' do
    Datadog::Contrib::Rails::Framework.configure({})
    tracer = Rails.configuration.datadog_trace[:tracer]
    assert_equal(tracer.services, 'rails-app' => { 'app' => 'rails', 'app_type' => 'web' })
  end
end
