require 'helper'
require 'net/http'
require 'ddtrace'
require 'ddtrace/contrib/rack/middlewares'

require 'rack/test'

class RackBaseTest < Minitest::Test
  include Rack::Test::Methods

  # rubocop:disable Metrics/MethodLength
  def app
    tracer = @tracer

    # rubocop:disable Metrics/BlockLength
    Rack::Builder.new do
      use Datadog::Contrib::Rack::TraceMiddleware

      map '/success/' do
        run(proc { |_env| [200, { 'Content-Type' => 'text/html' }, 'OK'] })
      end

      map '/failure/' do
        run(proc { |_env| [400, { 'Content-Type' => 'text/html' }, 'KO'] })
      end

      map '/exception/' do
        run(proc { |_env| raise StandardError, 'Unable to process the request' })
      end

      map '/500/' do
        run(proc { |_env| [500, { 'Content-Type' => 'text/html' }, 'KO'] })
      end

      map '/nomemory/' do
        run(proc { |_env| raise NoMemoryError, 'Non-standard error' })
      end

      map '/app/' do
        run(proc do |env|
          # this should be considered a web framework that can alter
          # the request span after routing / controller processing
          request_span = env[Datadog::Contrib::Rack::TraceMiddleware::RACK_REQUEST_SPAN]
          request_span.resource = 'GET /app/'
          request_span.set_tag('http.method', 'GET_V2')
          request_span.set_tag('http.status_code', 201)
          request_span.set_tag('http.url', '/app/static/')

          [200, { 'Content-Type' => 'text/html' }, 'OK']
        end)
      end

      map '/app/500/' do
        run(proc do |env|
          # this should be considered a web framework that can alter
          # the request span after routing / controller processing
          request_span = env[Datadog::Contrib::Rack::TraceMiddleware::RACK_REQUEST_SPAN]
          request_span.status = 1
          request_span.set_tag('error.stack', 'Handled exception')

          [500, { 'Content-Type' => 'text/html' }, 'OK']
        end)
      end

      map '/app/500/no_status/' do
        run(proc do |env|
          # this should be considered a web framework that can alter
          # the request span after routing / controller processing
          request_span = env[Datadog::Contrib::Rack::TraceMiddleware::RACK_REQUEST_SPAN]
          request_span.set_tag('error.stack', 'Handled exception')

          [500, { 'Content-Type' => 'text/html' }, 'OK']
        end)
      end

      map '/leak/' do
        handler = proc do
          tracer.trace('leaky-span-1')
          tracer.trace('leaky-span-2')
          tracer.trace('leaky-span-3')

          [200, { 'Content-Type' => 'text/html' }, 'OK']
        end

        run(handler)
      end
    end.to_app
  end

  def setup
    super

    # store the configuration and use a DummyTracer
    @tracer = get_test_tracer

    Datadog.configure do |c|
      c.tracer hostname: ENV.fetch('TEST_DDAGENT_HOST', 'localhost')
      c.use :http
      c.use :rack, tracer: @tracer
    end
  end

  def teardown
    super
    # reset the configuration
    Datadog.registry[:rack].reset_options!
  end
end
