require 'contrib/sinatra/tracer_test_base'

class MultiAppTest < TracerTestBase
  class FirstTestApp < Sinatra::Base
    register Datadog::Contrib::Sinatra::Tracer

    get '/endpoint' do
      '1'
    end
  end
end
