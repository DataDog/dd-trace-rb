# set this env var before doing anything else
ENV['DISABLE_DATADOG_RAILS'] = '1'

require 'helper'

require 'contrib/rails/test_helper'

class TracingControllerTest < ActionController::TestCase
  setup do
    @original_tracer = Rails.configuration.datadog_trace[:tracer]
    @tracer = get_test_tracer
    Rails.configuration.datadog_trace[:tracer] = @tracer
  end

  teardown do
    Rails.configuration.datadog_trace[:tracer] = @original_tracer
  end

  test 'rails must not be instrumented' do
    # make the request and assert the proper span
    get :index
    assert_response :success
    spans = @tracer.writer.spans()
    assert_equal(spans.length, 0, 'nothing should be traced, rails instrumentation totally disabled')
  end

  test 'manual instrumentation should still work' do
    @tracer.trace('a-test') do
      true
    end
    spans = @tracer.writer.spans()
    assert_equal(spans.length, 1, 'tracing, globally, is still enabled')
  end
end
