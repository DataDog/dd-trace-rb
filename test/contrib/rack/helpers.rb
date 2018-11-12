require 'helper'
require 'time'
require 'net/http'
require 'ddtrace'
require 'ddtrace/contrib/rack/middlewares'

require 'rack/test'

def wait_http_server(server, delay)
  delay.times do |i|
    uri = URI(server + '/')
    begin
      res = Net::HTTP.get_response(uri)
      return true if res.code == '200'
    rescue StandardError => e
      puts e if i >= 3 # display errors only when failing repeatedly
    end
    sleep 1
  end
  false
end

class RackBaseTest < Minitest::Test
  include Rack::Test::Methods

  # rubocop:disable Metrics/MethodLength
  def app
    tracer = @tracer
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

      map '/headers/' do
        run(proc do |_env|
          response_headers = {
            'Content-Type' => 'text/html',
            'Cache-Control' => 'max-age=3600',
            'ETag' => '"737060cd8c284d8af7ad3082f209582d"',
            'Expires' => 'Thu, 01 Dec 1994 16:00:00 GMT',
            'Last-Modified' => 'Tue, 15 Nov 1994 12:45:26 GMT',
            'X-Request-ID' => 'f058ebd6-02f7-4d3f-942e-904344e8cde5',
            'X-Fake-Response' => 'Don\'t tag me.'
          }
          [200, response_headers, 'OK']
        end)
      end
    end.to_app
  end

  def setup
    super

    # store the configuration and use a DummyTracer
    @tracer = get_test_tracer

    Datadog.configure do |c|
      c.use :http
      c.use :rack, tracer: @tracer
    end
  end

  def teardown
    super
    # reset the configuration
    Datadog.configuration[:rack].reset_options!
  end
end
