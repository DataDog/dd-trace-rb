require 'ddtrace/contrib/rack/middlewares'
require 'contrib/sinatra/rack_test_app'

class RackTest < TracerTestBase

  def app
    Rack::Builder.new do
      use Datadog::Contrib::Rack::TraceMiddleware

      map '/' do
        run RackTestApp.new
      end

    end.to_app
  end

  def setup
    super
    @tracer = get_test_tracer

    Datadog.configure do |c|
      c.use :rack, tracer: @tracer
      c.use :sinatra, tracer: @tracer
    end
  end

  def teardown
    super
    # reset the configuration
    Datadog.registry[:rack].reset_options!
    Datadog.registry[:sinatra].reset_options!
  end

  def test_set_rack_resource
    get '/endpoint'
    assert_equal(200, last_response.status)

    spans = @tracer.writer.spans()
    assert_equal(2, spans.length)

    rack_span = spans[0]
    assert_equal('rack', rack_span.service)
    assert_equal('GET /endpoint', rack_span.resource)

    sinatra_span = spans[1]
    assert_equal('sinatra', sinatra_span.service)
    assert_equal('GET /endpoint', sinatra_span.resource)
  end

end