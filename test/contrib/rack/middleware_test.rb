require 'contrib/rack/helpers'

# rubocop:disable Metrics/ClassLength
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
    assert_equal('rack', span.service)
    assert_equal('GET 200', span.resource)
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
    assert_equal('rack', span.service)
    assert_equal('POST 200', span.resource)
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
    assert_equal('rack', span.service)
    assert_equal('GET 200', span.resource)
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
    assert_equal('rack', span.service)
    assert_equal('GET 404', span.resource)
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
    assert_equal('rack', span.service)
    assert_equal('GET 400', span.resource)
    assert_equal('GET', span.get_tag('http.method'))
    assert_equal('400', span.get_tag('http.status_code'))
    assert_equal('/failure/', span.get_tag('http.url'))
    assert_equal(0, span.status)
    assert_nil(span.parent)
  end

  def test_request_middleware_exception
    # ensure the Rack request is properly traced even if
    # there is an exception
    assert_raises do
      get '/exception/'
    end

    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)

    span = spans[0]
    assert_equal('rack.request', span.name)
    assert_equal('http', span.span_type)
    assert_equal('rack', span.service)
    assert_equal('GET', span.resource)
    assert_equal('GET', span.get_tag('http.method'))
    assert_nil(span.get_tag('http.status_code'))
    assert_equal('/exception/', span.get_tag('http.url'))
    assert_equal('StandardError', span.get_tag('error.type'))
    assert_equal('Unable to process the request', span.get_tag('error.msg'))
    refute_nil(span.get_tag('error.stack'))
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
    assert_equal('rack', span.service)
    assert_equal('GET /app/', span.resource)
    assert_equal('GET_V2', span.get_tag('http.method'))
    assert_equal('201', span.get_tag('http.status_code'))
    assert_equal('/app/static/', span.get_tag('http.url'))
    assert_equal(0, span.status)
    assert_nil(span.parent)
  end

  def test_request_middleware_500
    # ensure that a Rack application that returns 500 without
    # raising an Exception is properly identified as an error
    get '/500/'
    assert last_response.status == 500

    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)

    span = spans[0]
    assert_equal('rack.request', span.name)
    assert_equal('http', span.span_type)
    assert_equal('rack', span.service)
    assert_equal('GET 500', span.resource)
    assert_equal('GET', span.get_tag('http.method'))
    assert_equal('500', span.get_tag('http.status_code'))
    assert_equal('/500/', span.get_tag('http.url'))
    assert_nil(span.get_tag('error.stack'))
    assert_equal(1, span.status)
    assert_nil(span.parent)
  end

  def test_request_middleware_500_handled
    # ensure that a Rack application that returns 500 and that
    # handles the exception properly, is identified as an error
    get '/app/500/'
    assert last_response.status == 500

    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)

    span = spans[0]
    assert_equal('rack.request', span.name)
    assert_equal('http', span.span_type)
    assert_equal('rack', span.service)
    assert_equal('GET 500', span.resource)
    assert_equal('GET', span.get_tag('http.method'))
    assert_equal('500', span.get_tag('http.status_code'))
    assert_equal('/app/500/', span.get_tag('http.url'))
    assert_equal(1, span.status)
    assert_equal('Handled exception', span.get_tag('error.stack'))
    assert_nil(span.parent)
  end

  def test_request_middleware_500_handled_without_status
    # ensure that a Rack application that returns 500 and that
    # handles the exception without setting the Span status,
    # is identified as an error
    get '/app/500/no_status/'
    assert last_response.status == 500

    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)

    span = spans[0]
    assert_equal('rack.request', span.name)
    assert_equal('http', span.span_type)
    assert_equal('rack', span.service)
    assert_equal('GET 500', span.resource)
    assert_equal('GET', span.get_tag('http.method'))
    assert_equal('500', span.get_tag('http.status_code'))
    assert_equal('/app/500/no_status/', span.get_tag('http.url'))
    assert_equal(1, span.status)
    assert_equal('Handled exception', span.get_tag('error.stack'))
    assert_nil(span.parent)
  end

  def test_request_middleware_non_standard_error
    # ensure the Rack request is properly traced even if
    # there is an exception, and this is not a standard error
    assert_raises NoMemoryError do
      get '/nomemory/'
    end

    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)

    span = spans[0]
    assert_equal('rack.request', span.name)
    assert_equal('http', span.span_type)
    assert_equal('rack', span.service)
    assert_equal('GET', span.resource)
    assert_equal('GET', span.get_tag('http.method'))
    assert_nil(span.get_tag('http.status_code'))
    assert_equal('/nomemory/', span.get_tag('http.url'))
    assert_equal('NoMemoryError', span.get_tag('error.type'))
    assert_equal('Non-standard error', span.get_tag('error.msg'))
    refute_nil(span.get_tag('error.stack'))
    assert_equal(1, span.status)
    assert_nil(span.parent)
  end

  def test_middleware_context_cleaning
    get '/leak'
    get '/success'

    assert_equal(0, @tracer.provider.context.trace.length)
    assert_equal(1, @tracer.writer.spans.length)
  end
end

class CustomTracerTest < RackBaseTest
  def app
    tracer = @tracer
    service = 'custom-rack'

    Rack::Builder.new do
      use Datadog::Contrib::Rack::TraceMiddleware, tracer: tracer, default_service: service

      map '/' do
        run(proc { |_env| [200, { 'Content-Type' => 'text/html' }, 'OK'] })
      end
    end
  end

  def test_request_middleware_custom_service
    # ensure the Rack request is properly traced
    get '/'
    assert last_response.ok?

    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)

    span = spans[0]
    assert_equal('rack.request', span.name)
    assert_equal('http', span.span_type)
    assert_equal('custom-rack', span.service)
    assert_equal('GET 200', span.resource)
    assert_equal('GET', span.get_tag('http.method'))
    assert_equal('200', span.get_tag('http.status_code'))
    assert_equal('/', span.get_tag('http.url'))
    assert_equal(0, span.status)
    assert_nil(span.parent)
  end
end

class RackBaseTest < Minitest::Test
  def test_middleware_builder_defaults
    # by default it should have a Tracer and a service
    middleware = Datadog::Contrib::Rack::TraceMiddleware.new(proc {})
    refute_nil(middleware)
    assert_equal(middleware.instance_eval { @options[:tracer] }, Datadog.tracer)
    assert_equal(middleware.instance_eval { @options[:default_service] }, 'rack')
  end

  def test_middleware_builder
    # it should set the tracer and the service
    tracer = get_test_tracer()
    middleware = Datadog::Contrib::Rack::TraceMiddleware.new(proc {}, tracer: tracer, default_service: 'custom-rack')
    refute_nil(middleware)
    assert_equal(middleware.instance_eval { @options[:tracer] }, tracer)
    assert_equal(middleware.instance_eval { @options[:default_service] }, 'custom-rack')
  end
end
