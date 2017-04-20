require 'helper'
require 'rack/test'

require 'grape'
require 'ddtrace/pin'
require 'ddtrace/contrib/grape/patcher'

class TestingAPI < Grape::API
  desc 'Returns a success message'
  get :success do
    'OK'
  end
end

class BaseAPITest < MiniTest::Test
  include Rack::Test::Methods

  def app
    TestingAPI
  end

  def setup
    # patch Grape and use a dummy tracer
    Datadog::Contrib::Grape::Patcher.patch()
    @tracer = get_test_tracer()
    pin = Datadog::Pin.get_from(::Grape)
    pin.tracer = @tracer
  end

  def teardown
    # unpatch Grape
    Datadog::Contrib::Grape::Patcher.unpatch()
  end
end
