
require 'contrib/sinatra/tracer_test_base'

class DisabledTracerTest < ::TracerTestBase
  class DisabledTracerTestApp < Sinatra::Application
    get '/request' do
      'hello world'
    end
  end

  def app
    DisabledTracerTestApp
  end

  def setup
    @writer = FauxWriter.new()
    app().set :datadog_test_writer, @writer

    tracer = Datadog::Tracer.new(writer: @writer)
    Datadog.configuration.use(:sinatra, tracer: tracer, enabled: false)

    super
  end

  def test_request
    get '/request'
    assert_equal(200, last_response.status)

    spans = @writer.spans()
    assert_equal(0, spans.length)
  end
end
