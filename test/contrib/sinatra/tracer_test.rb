require 'contrib/sinatra/tracer_test_base'

# rubocop:disable Metrics/ClassLength
class TracerTest < TracerTestBase
  def app
    @app ||= Class.new(Sinatra::Application) do
      get '/request' do
        headers['X-Request-Id'] = request.env['HTTP_X_REQUEST_ID']
        'hello world'
      end

      get '/bad-request' do
        halt 400, 'bad request'
      end

      get '/error' do
        halt 500, 'server error'
      end

      get '/exception' do
        raise StandardError, 'something bad'
      end

      get '/wildcard/*' do
        params['splat'][0]
      end

      get '/template' do
        erb :msg, locals: { msg: 'hello' }
      end

      get '/literal-template' do
        erb '<%= msg %>', locals: { msg: 'hello' }
      end
    end
  end

  def setup
    @app = nil
    @writer = FauxWriter.new

    tracer = Datadog::Tracer.new(writer: @writer, enabled: true)
    Datadog.configuration.use(:sinatra, tracer: tracer)

    app.set :datadog_test_writer, @writer

    super
  end

  def test_service_name
    previous_name = Datadog.configuration[:sinatra][:service_name]
    Datadog.configuration.use(:sinatra, service_name: 'my-sinatra-app')

    get '/request'
    assert_equal(200, last_response.status)

    spans = @writer.spans
    assert_equal(1, spans.length)

    span = spans[0]
    assert_equal('my-sinatra-app', span.service)
  ensure
    Datadog.configuration.use(:sinatra, service_name: previous_name)
  end

  def test_request
    get '/request#foo?a=1'
    assert_equal(200, last_response.status)

    spans = @writer.spans
    assert_equal(1, spans.length)

    span = spans[0]
    assert_equal('sinatra', span.service)
    assert_equal('GET /request', span.resource)
    assert_equal('GET', span.get_tag(Datadog::Ext::HTTP::METHOD))
    assert_equal('/request', span.get_tag(Datadog::Ext::HTTP::URL))
    assert_equal(Datadog::Ext::HTTP::TYPE, span.span_type)
    assert_equal(0, span.status)
    assert_nil(span.parent)
  end

  def test_distributed_request
    # Enable distributed tracing
    Datadog.configuration.use(:sinatra, distributed_tracing: true)

    response = get '/request', {},
                   'HTTP_X_DATADOG_TRACE_ID' => '1',
                   'HTTP_X_DATADOG_PARENT_ID' => '2',
                   'HTTP_X_DATADOG_SAMPLING_PRIORITY' => Datadog::Ext::Priority::USER_KEEP.to_s

    assert_equal(200, response.status)

    # Check spans
    spans = @writer.spans
    assert_equal(1, spans.length)

    # Check span
    span = spans[0]
    assert_equal(1, span.trace_id)
    assert_equal(2, span.parent_id)
    assert_equal(2.0, span.get_metric('_sampling_priority_v1'))
  ensure
    # Disable distributed tracing
    Datadog.configuration.use(:sinatra, distributed_tracing: false)
  end

  def test_bad_request
    get '/bad-request'
    assert_equal(400, last_response.status)

    spans = @writer.spans
    assert_equal(1, spans.length)

    span = spans[0]
    assert_equal('sinatra', span.service)
    assert_equal('GET /bad-request', span.resource)
    assert_equal('GET', span.get_tag(Datadog::Ext::HTTP::METHOD))
    assert_equal('/bad-request', span.get_tag(Datadog::Ext::HTTP::URL))
    assert_nil(span.get_tag(Datadog::Ext::Errors::TYPE))
    assert_nil(span.get_tag(Datadog::Ext::Errors::MSG))
    assert_equal(Datadog::Ext::HTTP::TYPE, span.span_type)
    assert_equal(0, span.status)
    assert_nil(span.parent)
  end

  def test_error
    get '/error'
    assert_equal(500, last_response.status)

    spans = @writer.spans
    assert_equal(1, spans.length)

    span = spans[0]
    assert_equal('sinatra', span.service)
    assert_equal('GET /error', span.resource)
    assert_equal('GET', span.get_tag(Datadog::Ext::HTTP::METHOD))
    assert_equal('/error', span.get_tag(Datadog::Ext::HTTP::URL))
    assert_nil(span.get_tag(Datadog::Ext::Errors::TYPE))
    assert_nil(span.get_tag(Datadog::Ext::Errors::MSG))
    assert_equal(Datadog::Ext::HTTP::TYPE, span.span_type)
    assert_equal(1, span.status)
    assert_nil(span.parent)
  end

  def test_exception
    get '/exception'
    assert_equal(500, last_response.status)

    spans = @writer.spans
    assert_equal(1, spans.length)

    span = spans[0]
    assert_equal('sinatra', span.service)
    assert_equal('GET /exception', span.resource)
    assert_equal('GET', span.get_tag(Datadog::Ext::HTTP::METHOD))
    assert_equal('/exception', span.get_tag(Datadog::Ext::HTTP::URL))
    assert_equal('StandardError', span.get_tag(Datadog::Ext::Errors::TYPE))
    assert_equal('something bad', span.get_tag(Datadog::Ext::Errors::MSG))
    assert_equal(Datadog::Ext::HTTP::TYPE, span.span_type)
    assert_equal(1, span.status)
    assert_nil(span.parent)
  end

  def test_wildcard
    get '/wildcard/1/2/3'
    assert_equal(200, last_response.status)

    spans = @writer.spans
    assert_equal(1, spans.length)

    span = spans[0]
    assert_equal('sinatra', span.service)
    assert_equal('GET /wildcard/*', span.resource)
    assert_equal('GET', span.get_tag(Datadog::Ext::HTTP::METHOD))
    assert_equal('/wildcard/1/2/3', span.get_tag(Datadog::Ext::HTTP::URL))
    assert_equal(Datadog::Ext::HTTP::TYPE, span.span_type)
    assert_equal(0, span.status)
    assert_nil(span.parent)
  end

  def test_template
    get '/template'
    assert_equal(200, last_response.status)

    spans = @writer.spans
    assert_equal(3, spans.length)

    child1, child2, root = spans

    assert_equal('sinatra', child2.service)
    assert_equal('sinatra.render_template', child2.resource)
    assert_equal('layout', child2.get_tag('sinatra.template_name'))
    assert_equal(0, child2.status)
    assert_equal(child1, child2.parent)

    assert_equal('sinatra', child1.service)
    assert_equal('sinatra.render_template', child1.resource)
    assert_equal('msg', child1.get_tag('sinatra.template_name'))
    assert_equal(0, child1.status)
    assert_equal(root, child1.parent)

    assert_equal('sinatra', root.service)
    assert_equal('GET /template', root.resource)
    assert_equal('GET', root.get_tag(Datadog::Ext::HTTP::METHOD))
    assert_equal('/template', root.get_tag(Datadog::Ext::HTTP::URL))
    assert_equal(Datadog::Ext::HTTP::TYPE, root.span_type)
    assert_equal(0, root.status)
    assert_nil(root.parent)
  end

  def test_literal_template
    get '/literal-template'
    assert_equal(200, last_response.status)

    spans = @writer.spans
    assert_equal(3, spans.length)

    child1, child2, root = spans

    assert_equal('sinatra', child2.service)
    assert_equal('sinatra.render_template', child2.resource)
    assert_equal('layout', child2.get_tag('sinatra.template_name'))
    assert_equal(0, child2.status)
    assert_equal(child1, child2.parent)

    assert_equal('sinatra', child1.service)
    assert_equal('sinatra.render_template', child1.resource)
    assert_nil(child1.get_tag('sinatra.template_name'))
    assert_equal(0, child1.status)
    assert_equal(root, child1.parent)

    assert_equal('sinatra', root.service)
    assert_equal('GET /literal-template', root.resource)
    assert_equal('GET', root.get_tag(Datadog::Ext::HTTP::METHOD))
    assert_equal('/literal-template', root.get_tag(Datadog::Ext::HTTP::URL))
    assert_equal(Datadog::Ext::HTTP::TYPE, root.span_type)
    assert_equal(0, root.status)
    assert_nil(root.parent)
  end

  def test_tagging_default_connection_headers
    request_id = SecureRandom.uuid
    get '/request', {}, 'HTTP_X_REQUEST_ID' => request_id

    assert_equal(200, last_response.status)

    spans = @writer.spans
    assert_equal(1, spans.length)

    span = spans[0]
    assert_equal('sinatra', span.service)
    assert_equal('GET /request', span.resource)
    assert_equal('GET', span.get_tag(Datadog::Ext::HTTP::METHOD))
    assert_equal('/request', span.get_tag(Datadog::Ext::HTTP::URL))
    assert_equal(Datadog::Ext::HTTP::TYPE, span.span_type)
    assert_equal(request_id, span.get_tag('http.response.headers.x_request_id'))
    assert_equal('text/html;charset=utf-8', span.get_tag('http.response.headers.content_type'))

    assert_equal(0, span.status)
    assert_nil(span.parent)
  end

  def test_tagging_configured_connection_headers
    Datadog.configuration.use(:sinatra,
                              headers: {
                                response: ['Content-Type'],
                                request: ['X-Request-Header']
                              })

    request_headers = {
      'HTTP_X_REQUEST_HEADER' => 'header_value',
      'HTTP_X_HEADER' => "don't tag me"
    }

    get '/request#foo?a=1', {}, request_headers

    assert_equal(200, last_response.status)

    spans = @writer.spans
    assert_equal(1, spans.length)

    span = spans[0]
    assert_equal('sinatra', span.service)
    assert_equal('GET /request', span.resource)
    assert_equal('GET', span.get_tag(Datadog::Ext::HTTP::METHOD))
    assert_equal('/request', span.get_tag(Datadog::Ext::HTTP::URL))
    assert_equal(Datadog::Ext::HTTP::TYPE, span.span_type)
    assert_equal('header_value', span.get_tag('http.request.headers.x_request_header'))
    assert_equal('text/html;charset=utf-8', span.get_tag('http.response.headers.content_type'))
    assert_nil(span.get_tag('http.request.headers.x_header'))

    assert_equal(0, span.status)
    assert_nil(span.parent)
  ensure
    Datadog.configuration.use(
      :sinatra,
      headers: Datadog::Contrib::Sinatra::Configuration::Settings::DEFAULT_HEADERS
    )
  end
end
