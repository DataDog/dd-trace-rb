require 'grape'
require 'helper'

require 'ddtrace'
require 'ddtrace/pin'
require 'ddtrace/contrib/grape/patcher'
require 'ddtrace/contrib/rack/middlewares'

require 'rack/test'

# patch Grape before the application
Datadog::Contrib::Grape::Patcher.patch()

class RackTestingAPI < Grape::API
  desc 'Returns a success message'
  get :success do
    'OK'
  end

  desc 'Returns an error'
  get :hard_failure do
    raise StandardError, 'Ouch!'
  end
end

class BaseRackAPITest < MiniTest::Test
  include Rack::Test::Methods

  def app
    tracer = @tracer

    # create a custom Rack application with the Rack middleware and a Grape API
    Rack::Builder.new do
      use Datadog::Contrib::Rack::TraceMiddleware, tracer: tracer
      map '/api/' do
        run RackTestingAPI
      end
    end.to_app
  end

  def setup
    # use a dummy tracer
    @tracer = get_test_tracer()
    pin = Datadog::Pin.get_from(::Grape)
    pin.tracer = @tracer
    super
  end
end
