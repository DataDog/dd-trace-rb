require 'ddtrace'
require 'ddtrace/contrib/rack/middlewares'

class RackTest < TracerTestBase

  class MiddlewareApp < Sinatra::Base
    register Datadog::Contrib::Sinatra::Tracer

    get '/middleware_endpoint' do
      'ok'
    end
  end

  class Application < Sinatra::Application
    get '/application_endpoint' do
      '1'
    end
  end

  def app
    Rack::Builder.new do
      use Datadog::Contrib::Rack::TraceMiddleware

      use MiddlewareApp
      run Application.new

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

  def test_set_rack_resource_from_app
    assert_rack_resource('/application_endpoint', 'GET /application_endpoint')
  end

  def test_set_rack_resource_from_middleware_app
    assert_rack_resource('/middleware_endpoint', 'GET /middleware_endpoint')
  end

  private

  def assert_rack_resource(url, resource)
    get url
    assert_equal(200, last_response.status)

    spans = @tracer.writer.spans()

    rack_span = spans[0]
    assert_equal('rack', rack_span.service)
    assert_equal(resource, rack_span.resource)
  end

end