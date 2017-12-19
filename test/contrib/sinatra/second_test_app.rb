require 'contrib/sinatra/tracer_test_base'

class MultiAppTest < TracerTestBase
  class SecondTestApp < Sinatra::Base
    register Datadog::Contrib::Sinatra::Tracer

    get '/endpoint' do
      '2'
    end
  end
end
