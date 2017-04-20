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

  test 'error in the controller must be traced' do
    assert_raises ZeroDivisionError do
      get :error
    end
    spans = @tracer.writer.spans()
    assert_equal(spans.length, 1)

    span = spans[0]
    assert_equal(span.name, 'rails.action_controller')
    assert_equal(span.status, 1)
    assert_equal(span.span_type, 'http')
    assert_equal(span.resource, 'TracingController#error')
    assert_equal(span.get_tag('rails.route.action'), 'error')
    assert_equal(span.get_tag('rails.route.controller'), 'TracingController')
    assert_equal(span.get_tag('error.type'), 'ZeroDivisionError')
    assert_equal(span.get_tag('error.msg'), 'divided by 0')
  end

  test 'error in the template must be traced' do
    assert_raises ::ActionView::Template::Error do
      get :error_template
    end
    spans = @tracer.writer.spans()
    assert_equal(spans.length, 2)

    span_template = spans[0]
    assert_equal(span_template.name, 'rails.render_template')
    assert_equal(span_template.status, 1)
    assert_equal(span_template.span_type, 'template')
    assert_equal(span_template.resource, 'rails.render_template')
    assert_equal(span_template.get_tag('rails.template_name'), 'tracing/error.html.erb')
    assert_equal(span_template.get_tag('rails.layout'), 'layouts/application')
    assert_equal(span_template.get_tag('error.type'), 'ActionView::Template::Error')
    assert_equal(span_template.get_tag('error.msg'), 'divided by 0')

    span_request = spans[1]
    assert_equal(span_request.name, 'rails.action_controller')
    assert_equal(span_request.status, 1)
    assert_equal(span_request.span_type, 'http')
    assert_equal(span_request.resource, 'TracingController#error_template')
    assert_equal(span_request.get_tag('rails.route.action'), 'error_template')
    assert_equal(span_request.get_tag('rails.route.controller'), 'TracingController')
    assert_equal(span_request.get_tag('error.type'), 'ActionView::Template::Error')
    assert_equal(span_request.get_tag('error.msg'), 'divided by 0')
  end

  test 'error in the template partials must be traced' do
    assert_raises ::ActionView::Template::Error do
      get :error_partial
    end
    spans = @tracer.writer.spans()
    assert_equal(spans.length, 3)

    span_partial = spans[0]
    assert_equal(span_partial.name, 'rails.render_partial')
    assert_equal(span_partial.status, 1)
    assert_equal(span_partial.span_type, 'template')
    assert_equal(span_partial.resource, 'rails.render_partial')
    assert_equal(span_partial.get_tag('rails.template_name'), 'tracing/_inner_error.html.erb')
    assert_equal(span_partial.get_tag('error.type'), 'ActionView::Template::Error')
    assert_equal(span_partial.get_tag('error.msg'), 'divided by 0')

    span_template = spans[1]
    assert_equal(span_template.name, 'rails.render_template')
    assert_equal(span_template.status, 1)
    assert_equal(span_template.span_type, 'template')
    assert_equal(span_template.resource, 'rails.render_template')
    assert_equal(span_template.get_tag('rails.template_name'), 'tracing/error_partial.html.erb')
    assert_equal(span_template.get_tag('rails.layout'), 'layouts/application')
    assert_equal(span_template.get_tag('error.type'), 'ActionView::Template::Error')
    assert_equal(span_template.get_tag('error.msg'), 'divided by 0')

    span_request = spans[2]
    assert_equal(span_request.name, 'rails.action_controller')
    assert_equal(span_request.status, 1)
    assert_equal(span_request.span_type, 'http')
    assert_equal(span_request.resource, 'TracingController#error_partial')
    assert_equal(span_request.get_tag('rails.route.action'), 'error_partial')
    assert_equal(span_request.get_tag('rails.route.controller'), 'TracingController')
    assert_equal(span_request.get_tag('error.type'), 'ActionView::Template::Error')
    assert_equal(span_request.get_tag('error.msg'), 'divided by 0')
  end
end
