require 'helper'
require 'rack/test'

require 'grape'
require 'ddtrace/pin'
require 'ddtrace/contrib/grape/patcher'

# patch Grape before the application
Datadog::Contrib::Grape::Patcher.patch()

class TestingAPI < Grape::API
  namespace :base do
    desc 'Returns a success message'
    get :success do
      'OK'
    end

    desc 'Returns an error'
    get :hard_failure do
      raise StandardError, 'Ouch!'
    end
  end

  namespace :filtered do
    before do
      sleep(0.01)
    end

    after do
      sleep(0.01)
    end

    desc 'Returns a success message before and after filter processing'
    get :before_after do
      'OK'
    end
  end

  namespace :filtered_exception do
    before do
      raise StandardError, 'Ouch!'
    end

    desc 'Returns an error in the filter'
    get :before do
      'OK'
    end
  end
end

class BaseAPITest < MiniTest::Test
  include Rack::Test::Methods

  def app
    TestingAPI
  end
end
