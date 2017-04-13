require 'helper'

require 'contrib/rails/test_helper'

class TracingControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_tracer = Rails.configuration.datadog_trace[:tracer]
    @tracer = get_test_tracer
    Rails.configuration.datadog_trace[:tracer] = @tracer
  end

  teardown do
    Rails.configuration.datadog_trace[:tracer] = @original_tracer
  end

  test 'request is properly traced' do
    # make the request and assert the proper span
    get '/'
    assert_response :success
    spans = @tracer.writer.spans()
    assert_equal(spans.length, 2)

    span = spans[1]
    assert_equal(span.name, 'rails.request')
    assert_equal(span.span_type, 'http')
    assert_equal(span.resource, 'TracingController#index')
    assert_equal(span.get_tag('http.url'), '/')
    assert_equal(span.get_tag('http.method'), 'GET')
    assert_equal(span.get_tag('http.status_code'), '200')
    assert_equal(span.get_tag('rails.route.action'), 'index')
    assert_equal(span.get_tag('rails.route.controller'), 'TracingController')
  end

  test 'template rendering is properly traced' do
    # render the template and assert the proper span
    get '/'
    assert_response :success
    spans = @tracer.writer.spans()
    assert_equal(spans.length, 2)
    span = spans[0]
    assert_equal(span.name, 'rails.render_template')
    assert_equal(span.span_type, 'template')
    assert_equal(span.resource, 'rails.render_template')
    assert_equal(span.get_tag('rails.template_name'), 'tracing/index.html.erb')
    assert_equal(span.get_tag('rails.layout'), 'layouts/application')
  end

  test 'template partial rendering is properly traced' do
    # render the template and assert the proper span
    get '/partial'
    assert_response :success
    spans = @tracer.writer.spans()
    assert_equal(spans.length, 3)

    span_template = spans[1]
    span_partial = spans[0]
    assert_equal(span_partial.name, 'rails.render_partial')
    assert_equal(span_partial.span_type, 'template')
    assert_equal(span_partial.resource, 'rails.render_partial')
    assert_equal(span_partial.get_tag('rails.template_name'), 'tracing/_body.html.erb')
    assert_equal(span_partial.parent, span_template)
  end

  test 'a full request with database access on the template' do
    # render the endpoint
    get '/full'
    assert_response :success
    spans = @tracer.writer.spans()
    assert_equal(spans.length, 4)

    # assert the spans
    adapter_name = get_adapter_name()
    span_cache = spans[0]
    span_database = spans[1]
    span_template = spans[2]
    span_request = spans[3]
    assert_equal(span_cache.name, 'rails.cache')
    assert_equal(span_database.name, "#{adapter_name}.query")
    assert_equal(span_template.name, 'rails.render_template')
    assert_equal(span_request.name, 'rails.request')

    # assert the parenting
    assert_nil(span_request.parent)
    assert_equal(span_template.parent, span_request)
    assert_equal(span_database.parent, span_template)
    assert_equal(span_cache.parent, span_request)
  end

  test 'multiple calls should not leave an unfinished span in the local thread buffer' do
    get '/full'
    assert_response :success
    assert_nil(Thread.current[:datadog_span])

    get '/full'
    assert_response :success
    assert_nil(Thread.current[:datadog_span])
  end

  test 'error should be trapped and reported as such' do
    get '/error'
    assert_response :error

    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)
    span = spans[0]
    assert_equal('rails.request', span.name)
    assert_equal(1, span.status, 'span should be flagged as an error')
    assert_equal('ZeroDivisionError', span.get_tag('error.type'), 'type should contain the class name of the error')
    assert_equal('divided by 0', span.get_tag('error.msg'), 'msg should state we tried to divided by 0')
    assert_match(/ddtrace/, span.get_tag('error.stack'), 'stack should contain the call stack when error was raised')
    assert_match(/\n/, span.get_tag('error.stack'), 'stack should have multiple lines')
    assert_equal('500', span.get_tag('http.status_code'), 'status should be 500 error by default')
  end

  test 'http error code should be trapped and reported as such, even with no exception' do
    get '/soft_error'

    spans = @tracer.writer.spans()
    if Rails::VERSION::MAJOR.to_i >= 5
      assert_equal(1, spans.length)
    else
      assert_equal(2, spans.length, 'legacy code (rails <= 4) uses render with a status, so there is an extra render span')
    end
    span = spans[spans.length - 1]
    assert_equal('rails.request', span.name)
    assert_equal(1, span.status, 'span should be flagged as an error')
    assert_nil(span.get_tag('error.type'), 'type should be undefined')
    assert_nil(span.get_tag('error.msg'), 'msg should be empty')
    assert_match(/ddtrace/, span.get_tag('error.stack'), 'stack should contain the call stack when error was raised')
    assert_equal('520', span.get_tag('http.status_code'), 'status should be 520 Web server is returning an unknown error')
  end
end
