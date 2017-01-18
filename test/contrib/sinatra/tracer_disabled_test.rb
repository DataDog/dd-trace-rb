
require 'contrib/sinatra/tracer_test_base'

class DisabledTracerTest < ::TracerTestBase
  class DisabledTracerTestApp < Sinatra::Application
    configure do
      writer = FauxWriter.new()
      tracer = Datadog::Tracer.new(writer: writer)

      settings.datadog_tracer.configure(tracer: tracer, enabled: false)

      set :datadog_test_writer, writer
      set :datadog_test_tracer, tracer
    end

    get '/request' do
      'hello world'
    end
  end

  def app
    DisabledTracerTestApp
  end

  def setup
    @writer = app().settings.datadog_test_writer
    @writer.spans() # clear trace buffer
    super
  end

  def test_request
    get '/request'
    assert_equal(200, last_response.status)

    spans = @writer.spans()
    assert_equal(0, spans.length)
  end
end
