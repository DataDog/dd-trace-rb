require 'helper'

require 'contrib/rails/test_helper'

# rubocop:disable Metrics/ClassLength
class TracingControllerTest < ActionController::TestCase
  setup do
    @original_tracer = Datadog.configuration[:rails][:tracer]
    @tracer = get_test_tracer
    Datadog.configuration[:rails][:tracer] = @tracer
  end

  teardown do
    Datadog.configuration[:rails][:tracer] = @original_tracer
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
    assert_equal(span.span_type, 'web')
    assert_equal(span.resource, 'TracingController#error')
    assert_equal(span.get_tag('rails.route.action'), 'error')
    assert_equal(span.get_tag('rails.route.controller'), 'TracingController')
    assert_equal(span.get_tag('error.type'), 'ZeroDivisionError')
    assert_equal(span.get_tag('error.msg'), 'divided by 0')
  end

  test '404 should not be traced as errors' do
    assert_raises ActionController::RoutingError do
      get :not_found
    end

    spans = @tracer.writer.spans()
    assert_equal(spans.length, 1)

    span = spans[0]
    assert_equal(span.name, 'rails.action_controller')
    assert_equal(span.span_type, 'web')
    assert_equal(span.resource, 'TracingController#not_found')
    assert_equal(span.get_tag('rails.route.action'), 'not_found')
    assert_equal(span.get_tag('rails.route.controller'), 'TracingController')
    # Stop here for old Rails versions, which have no ActionDispatch::ExceptionWrapper
    return if Rails.version < '3.2.22.5'
    assert_equal(span.status, 0)
    assert_nil(span.get_tag('error.type'))
    assert_nil(span.get_tag('error.msg'))
  end

  test 'missing rendering should close the template Span' do
    skip 'Recent versions use events, and cannot suffer from this issue' if Rails.version >= '4.0.0'

    # this route raises an exception, but the notification `render_template.action_view`
    # is not fired, causing unfinished spans; this test protects from regressions
    assert_raises ::ActionView::MissingTemplate do
      get :missing_template
    end
    spans = @tracer.writer.spans()
    assert_equal(spans.length, 2)

    span_request, span_template = spans

    assert_equal(span_request.name, 'rails.action_controller')
    assert_equal(span_request.status, 1)
    assert_equal(span_request.span_type, 'web')
    assert_equal(span_request.resource, 'TracingController#missing_template')
    assert_equal(span_request.get_tag('rails.route.action'), 'missing_template')
    assert_equal(span_request.get_tag('rails.route.controller'), 'TracingController')
    assert_equal(span_request.get_tag('error.type'), 'ActionView::MissingTemplate')
    assert_includes(span_request.get_tag('error.msg'), 'Missing template views/tracing/ouch.not.here')

    assert_equal(span_template.name, 'rails.render_template')
    assert_equal(span_template.status, 1)
    assert_equal(span_template.span_type, 'template')
    assert_equal(span_template.resource, 'rails.render_template')
    assert_nil(span_template.get_tag('rails.template_name'))
    assert_nil(span_template.get_tag('rails.layout'))
    assert_equal(span_template.get_tag('error.type'), 'ActionView::MissingTemplate')
    assert_includes(span_template.get_tag('error.msg'), 'Missing template views/tracing/ouch.not.here')
  end

  test 'missing partial rendering should close the template Span' do
    skip 'Recent versions use events, and cannot suffer from this issue' if Rails.version >= '4.0.0'

    # this route raises an exception, but the notification `render_partial.action_view`
    # is not fired, causing unfinished spans; this test protects from regressions
    assert_raises ::ActionView::Template::Error do
      get :missing_partial
    end

    error_msg = if Rails.version > '3.2.22.5'
                  'Missing partial tracing/_ouch.html.erb'
                else
                  'Missing partial tracing/ouch.html'
                end

    spans = @tracer.writer.spans()
    assert_equal(spans.length, 3)
    span_request, span_partial, span_template = spans

    assert_equal(span_request.name, 'rails.action_controller')
    assert_equal(span_request.status, 1)
    assert_equal(span_request.span_type, 'web')
    assert_equal(span_request.resource, 'TracingController#missing_partial')
    assert_equal(span_request.get_tag('rails.route.action'), 'missing_partial')
    assert_equal(span_request.get_tag('rails.route.controller'), 'TracingController')
    assert_equal(span_request.get_tag('error.type'), 'ActionView::Template::Error')
    assert_includes(span_request.get_tag('error.msg'), error_msg)

    assert_equal(span_partial.name, 'rails.render_partial')
    assert_equal(span_partial.status, 1)
    assert_equal(span_partial.span_type, 'template')
    assert_equal(span_partial.resource, 'rails.render_partial')
    assert_nil(span_partial.get_tag('rails.template_name'))
    assert_nil(span_partial.get_tag('rails.layout'))
    assert_equal(span_partial.get_tag('error.type'), 'ActionView::MissingTemplate')
    assert_includes(span_partial.get_tag('error.msg'), error_msg)

    assert_equal(span_template.name, 'rails.render_template')
    assert_equal(span_template.status, 1)
    assert_equal(span_template.span_type, 'template')
    assert_equal(span_template.resource, 'tracing/missing_partial.html.erb')
    assert_equal(span_template.get_tag('rails.template_name'), 'tracing/missing_partial.html.erb')
    assert_equal(span_template.get_tag('rails.layout'), 'layouts/application')
    assert_includes(span_template.get_tag('error.msg'), error_msg)
    assert_equal(span_template.get_tag('error.type'), 'ActionView::Template::Error')
  end

  test 'error in the template must be traced' do
    assert_raises ::ActionView::Template::Error do
      get :error_template
    end
    spans = @tracer.writer.spans()
    assert_equal(spans.length, 2)

    span_request, span_template = spans

    assert_equal(span_request.name, 'rails.action_controller')
    assert_equal(span_request.status, 1)
    assert_equal(span_request.span_type, 'web')
    assert_equal(span_request.resource, 'TracingController#error_template')
    assert_equal(span_request.get_tag('rails.route.action'), 'error_template')
    assert_equal(span_request.get_tag('rails.route.controller'), 'TracingController')
    assert_equal(span_request.get_tag('error.type'), 'ActionView::Template::Error')
    assert_equal(span_request.get_tag('error.msg'), 'divided by 0')

    assert_equal(span_template.name, 'rails.render_template')
    assert_equal(span_template.status, 1)
    assert_equal(span_template.span_type, 'template')
    assert_includes(span_template.resource, 'tracing/error.html')
    if Rails.version >= '3.2.22.5'
      assert_equal(span_template.resource, 'tracing/error.html.erb')
      assert_equal(span_template.get_tag('rails.template_name'),
                   'tracing/error.html.erb')
    end
    assert_includes(span_template.get_tag('rails.template_name'), 'tracing/error.html')
    if Rails.version >= '3.2.22.5'
      assert_equal(span_template.get_tag('rails.layout'),
                   'layouts/application')
    end
    assert_includes(span_template.get_tag('rails.layout'), 'layouts/application')
    assert_equal(span_template.get_tag('error.type'), 'ActionView::Template::Error')
    assert_equal(span_template.get_tag('error.msg'), 'divided by 0')
  end

  test 'error in the template partials must be traced' do
    assert_raises ::ActionView::Template::Error do
      get :error_partial
    end
    spans = @tracer.writer.spans()
    assert_equal(spans.length, 3)

    span_request, span_partial, span_template = spans

    assert_equal(span_request.name, 'rails.action_controller')
    assert_equal(span_request.status, 1)
    assert_equal(span_request.span_type, 'web')
    assert_equal(span_request.resource, 'TracingController#error_partial')
    assert_equal(span_request.get_tag('rails.route.action'), 'error_partial')
    assert_equal(span_request.get_tag('rails.route.controller'), 'TracingController')
    assert_equal(span_request.get_tag('error.type'), 'ActionView::Template::Error')
    assert_equal(span_request.get_tag('error.msg'), 'divided by 0')

    assert_equal(span_partial.name, 'rails.render_partial')
    assert_equal(span_partial.status, 1)
    assert_equal(span_partial.span_type, 'template')
    assert_includes(span_partial.resource, 'tracing/_inner_error.html')
    if Rails.version >= '3.2.22.5'
      assert_equal(span_partial.resource, 'tracing/_inner_error.html.erb')
      assert_equal(span_partial.get_tag('rails.template_name'),
                   'tracing/_inner_error.html.erb')
    end
    assert_includes(span_partial.get_tag('rails.template_name'), 'tracing/_inner_error.html')
    assert_equal(span_partial.get_tag('error.type'), 'ActionView::Template::Error')
    assert_equal(span_partial.get_tag('error.msg'), 'divided by 0')

    assert_equal(span_template.name, 'rails.render_template')
    assert_equal(span_template.status, 1)
    assert_equal(span_template.span_type, 'template')
    assert_includes(span_template.resource, 'tracing/error_partial.html')
    if Rails.version >= '3.2.22.5'
      assert_equal(span_template.get_tag('rails.template_name'),
                   'tracing/error_partial.html.erb')
    end
    assert_includes(span_template.get_tag('rails.template_name'), 'tracing/error_partial.html')
    if Rails.version >= '3.2.22.5'
      assert_equal(span_template.get_tag('rails.layout'),
                   'layouts/application')
    end
    assert_includes(span_template.get_tag('rails.layout'), 'layouts/application')
    assert_equal(span_template.get_tag('error.type'), 'ActionView::Template::Error')
    assert_equal(span_template.get_tag('error.msg'), 'divided by 0')
  end
end
