
require 'contrib/sinatra/tracer_test_base'

class DisabledTracerTest < ::TracerTestBase
  def app
    @app ||= Class.new(Sinatra::Application) do
      get '/request' do
        'hello world'
      end
    end
  end

  def setup
    @app = nil
    @writer = FauxWriter.new

    tracer = Datadog::Tracer.new(writer: @writer, enabled: false)
    Datadog.configuration.use(:sinatra, tracer: tracer)

    app.set :datadog_test_writer, @writer

    super
  end

  def test_request
    get '/request'
    assert_equal(200, last_response.status)

    spans = @writer.spans
    assert_equal(0, spans.length)
  end
end
