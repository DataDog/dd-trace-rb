
require 'sinatra/base'
require 'ddtrace'
require 'ddtrace/contrib/sinatra/tracer'
require 'helper'
require 'rack/test'

class TracerTestBase < Minitest::Test
  include Rack::Test::Methods
end
