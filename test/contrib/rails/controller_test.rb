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

  test 'request is properly traced' do
    # make the request and assert the proper span
    get :index
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
    assert span.to_hash[:duration] > 0
  end

  test 'template rendering is properly traced' do
    # render the template and assert the proper span
    get :index
    assert_response :success
    spans = @tracer.writer.spans()
    assert_equal(spans.length, 2)
    span = spans[0]
    assert_equal(span.name, 'rails.render_template')
    assert_equal(span.span_type, nil)
    assert_equal(span.resource, 'rails.render_template')
    assert_equal(span.get_tag('rails.template_name'), 'tracing/index.html.erb')
    assert_equal(span.get_tag('rails.layout'), 'layouts/application')
    assert span.to_hash[:duration] > 0
  end

  test 'template partial rendering is properly traced' do
    # render the template and assert the proper span
    get :partial
    assert_response :success
    spans = @tracer.writer.spans()
    assert_equal(spans.length, 3)

    span_template = spans[1]
    span_partial = spans[0]
    assert_equal(span_partial.name, 'rails.render_partial')
    assert_equal(span_partial.span_type, nil)
    assert_equal(span_partial.resource, 'rails.render_partial')
    assert_equal(span_partial.get_tag('rails.template_name'), 'tracing/_body.html.erb')
    assert_equal(span_partial.parent, span_template)

    assert span_template.to_hash[:duration] > 0
    assert span_partial.to_hash[:duration] > 0
  end

  test 'a full request with database access on the template' do
    # render the endpoint
    get :full
    assert_response :success
    spans = @tracer.writer.spans()
    assert_equal(spans.length, 4)

    # assert the spans
    span_cache = spans[0]
    span_database = spans[1]
    span_template = spans[2]
    span_request = spans[3]
    assert_equal(span_cache.name, 'rails.cache')
    assert_equal(span_database.name, 'sqlite.query')
    assert_equal(span_template.name, 'rails.render_template')
    assert_equal(span_request.name, 'rails.request')

    # assert the parenting
    assert_equal(span_request.parent, nil)
    assert_equal(span_template.parent, span_request)
    assert_equal(span_database.parent, span_template)
    assert_equal(span_cache.parent, span_request)

    # assert they're finished
    assert span_request.to_hash[:duration] > 0
    assert span_template.to_hash[:duration] > 0
    assert span_database.to_hash[:duration] > 0
    assert span_cache.to_hash[:duration] > 0
  end

  test 'multiple calls should not leave an unfinished span in the local thread buffer' do
    get :full
    assert_response :success
    assert_equal(Thread.current[:datadog_span], nil)

    get :full
    assert_response :success
    assert_equal(Thread.current[:datadog_span], nil)
  end
end
