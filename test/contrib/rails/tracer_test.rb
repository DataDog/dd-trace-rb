require 'helper'
require 'contrib/rails/test_helper'

class TracingTest < ActionController::TestCase
  test 'correct initializer for ddtrace' do
    initializer = Rails.application.initializers.detect { |i| i.name == 'ddtrace.instrument' }
    assert initializer
  end

  test 'a tracer is available in the Rails config' do
    tracer = Rails.configuration.datadog_trace[:tracer]
    assert tracer
  end
end
