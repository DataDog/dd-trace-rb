require 'helper'

require 'contrib/rails/test_helper'

class CallbacksControllerTest < ActionController::TestCase
  setup do
    @original_tracer = Datadog.configuration[:rails][:tracer]
    @tracer = get_test_tracer
    Datadog.configure do |c|
      c.use :rails, tracer: @tracer, controller_callback_tracing: true
    end

    # If this isn't the first test to run, callbacks may not have been patched in.
    # Make sure they're activated by calling patch manually.
    Datadog::RailsActionPatcher.patch_callbacks
  end

  teardown do
    Datadog.configuration[:rails][:tracer] = @original_tracer
  end

  test 'request is properly traced' do
    if Datadog::Contrib::Rails::Patcher.controller_callback_tracing_supported?
      assert(Datadog::RailsActionPatcher.callbacks_patched?)

      get :index
      assert_response :success
      spans = @tracer.writer.spans
      assert_equal(4, spans.length)

      after_span, before_span, controller_span, action_span = spans

      # Before span
      assert_equal(before_span.name, 'active_support.callback')
      assert_equal(before_span.span_type, 'http')
      assert_equal(before_span.resource, 'before_request')
      assert_equal(before_span.get_tag('active_support.callback.name'), 'process_action')
      assert_equal(before_span.get_tag('active_support.callback.kind'), 'before')
      assert_equal(before_span.get_tag('active_support.callback.key'), 'before_request')

      # Action span
      assert_equal(action_span.name, 'rails.action_controller.process_action')
      assert_equal(action_span.span_type, 'http')
      assert_equal(action_span.resource, 'CallbacksController#index')

      # After span
      assert_equal(after_span.name, 'active_support.callback')
      assert_equal(after_span.span_type, 'http')
      assert_equal(after_span.resource, 'after_request')
      assert_equal(after_span.get_tag('active_support.callback.name'), 'process_action')
      assert_equal(after_span.get_tag('active_support.callback.kind'), 'after')
      assert_equal(after_span.get_tag('active_support.callback.key'), 'after_request')

      # Controller span
      assert_equal(controller_span.name, 'rails.action_controller')
      assert_equal(controller_span.span_type, 'http')
      assert_equal(controller_span.resource, 'CallbacksController#index')
      assert_equal(controller_span.get_tag('rails.route.action'), 'index')
      assert_equal(controller_span.get_tag('rails.route.controller'), 'CallbacksController')
    end
  end
end
