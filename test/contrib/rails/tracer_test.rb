require 'helper'

require 'contrib/rails/test_helper'

class TracerTest < ActionController::TestCase
  setup do
    # reinitialize the tracer with default settings
    Datadog::Contrib::Rails::Framework.configure({})
  end

  test 'correct initializer for ddtrace' do
    initializer = Rails.application.initializers.detect { |i| i.name == 'ddtrace.instrument' }
    assert initializer
  end

  test 'a tracer is available in the Rails config' do
    tracer = Rails.configuration.datadog_trace[:tracer]
    assert tracer
  end

  test 'a default service is properly set' do
    tracer = Rails.configuration.datadog_trace[:tracer]
    assert_equal(tracer.services, 'rails-app' => { 'app' => 'rails', 'app_type' => 'web' })
  end
end
