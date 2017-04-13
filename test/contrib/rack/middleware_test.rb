require 'contrib/rack/helpers'

class TracerTest < RackBaseTest
  def test_request_middleware_get
    # ensure the Rack request is properly traced
    get '/success/'
    assert last_response.ok?

    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)

    span = spans[0]
    assert_equal('rack.request', span.name)
    assert_equal('http', span.span_type)
    assert_equal('rack-app', span.service)
    assert_equal('rack.request', span.resource)
    assert_equal('GET', span.get_tag('http.method'))
    assert_equal('200', span.get_tag('http.status_code'))
    assert_equal('/success/', span.get_tag('http.url'))
    assert_equal(0, span.status)
    assert_nil(span.parent)
  end

  def test_request_middleware_post
    # ensure the Rack request is properly traced
    post '/success/'
    assert last_response.ok?

    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)

    span = spans[0]
    assert_equal('rack.request', span.name)
    assert_equal('http', span.span_type)
    assert_equal('rack-app', span.service)
    assert_equal('rack.request', span.resource)
    assert_equal('POST', span.get_tag('http.method'))
    assert_equal('200', span.get_tag('http.status_code'))
    assert_equal('/success/', span.get_tag('http.url'))
    assert_equal(0, span.status)
    assert_nil(span.parent)
  end

  def test_request_middleware_routes
    # ensure the Rack request is properly traced
    get '/success/100'
    assert last_response.ok?

    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)

    span = spans[0]
    assert_equal('rack.request', span.name)
    assert_equal('http', span.span_type)
    assert_equal('rack-app', span.service)
    assert_equal('rack.request', span.resource)
    assert_equal('GET', span.get_tag('http.method'))
    assert_equal('200', span.get_tag('http.status_code'))
    assert_equal('/success/100', span.get_tag('http.url'))
    assert_equal(0, span.status)
    assert_nil(span.parent)
  end

  def test_request_middleware_missing_application
    # ensure the Rack request is properly traced
    get '/not/exists/'
    assert last_response.not_found?

    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)

    span = spans[0]
    assert_equal('rack.request', span.name)
    assert_equal('http', span.span_type)
    assert_equal('rack-app', span.service)
    assert_equal('rack.request', span.resource)
    assert_equal('GET', span.get_tag('http.method'))
    assert_equal('404', span.get_tag('http.status_code'))
    assert_equal('/not/exists/', span.get_tag('http.url'))
    assert_equal(0, span.status)
    assert_nil(span.parent)
  end

  def test_request_middleware_bad_request
    # ensure the Rack request is properly traced when
    # the route is not found
    get '/failure/'
    assert last_response.status == 400

    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)

    span = spans[0]
    assert_equal('rack.request', span.name)
    assert_equal('http', span.span_type)
    assert_equal('rack-app', span.service)
    assert_equal('rack.request', span.resource)
    assert_equal('GET', span.get_tag('http.method'))
    assert_equal('400', span.get_tag('http.status_code'))
    assert_equal('/failure/', span.get_tag('http.url'))
    assert_equal(0, span.status)
    assert_nil(span.parent)
  end

  def test_request_middleware_exception
    # ensure the Rack request is properly traced even if
    # there is an exception
    assert_raise do
      get '/exception/'
    end

    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)

    span = spans[0]
    assert_equal('rack.request', span.name)
    assert_equal('http', span.span_type)
    assert_equal('rack-app', span.service)
    assert_equal('rack.request', span.resource)
    assert_equal('GET', span.get_tag('http.method'))
    assert_equal('/exception/', span.get_tag('http.url'))
    assert_equal('StandardError', span.get_tag('error.type'))
    assert_equal('Unable to process the request', span.get_tag('error.msg'))
    assert_not_nil(span.get_tag('error.stack'))
    assert_equal(1, span.status)
    assert_nil(span.parent)
  end

  def test_request_middleware_rack_app
    # ensure that a Rack application can update the request span with
    # all details available in the given route
    get '/app/posts/100'

    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)

    span = spans[0]
    assert_equal('rack.request', span.name)
    assert_equal('http', span.span_type)
    assert_equal('rack-app', span.service)
    assert_equal('GET /app/', span.resource)
    assert_equal('GET_V2', span.get_tag('http.method'))
    assert_equal('/app/static/', span.get_tag('http.url'))
    assert_equal(0, span.status)
    assert_nil(span.parent)
  end
end
