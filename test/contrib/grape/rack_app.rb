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
    # create a custom Rack application with the Rack middleware and a Grape API
    Rack::Builder.new do
      use Datadog::Contrib::Rack::TraceMiddleware
      map '/api/' do
        run RackTestingAPI
      end
    end.to_app
  end

  def setup
    super
    # store the configuration and use a DummyTracer
    @tracer = get_test_tracer

    Datadog.configure do |c|
      c.use :grape, tracer: @tracer
      c.use :rack, tracer: @tracer
    end
  end

  def teardown
    super
    # reset the configuration
    Datadog.configuration[:rack].reset!
    Datadog.configuration[:grape].reset!
  end
end
