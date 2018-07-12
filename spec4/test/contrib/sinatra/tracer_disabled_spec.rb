require('contrib/sinatra/tracer_test_base')
class DisabledTracerTest < ::TracerTestBase
  class DisabledTracerTestApp < Sinatra::Application
    get('/request') { 'hello world' }
  end
  def app
    DisabledTracerTestApp
  end
  before do
    @writer = FauxWriter.new
    app.set(:datadog_test_writer, @writer)
    tracer = Datadog::Tracer.new(writer: @writer, enabled: false)
    Datadog.configuration.use(:sinatra, tracer: tracer)
    super
  end
  it('request') do
    get('/request')
    expect(last_response.status).to(eq(200))
    spans = @writer.spans
    expect(spans.length).to(eq(0))
  end
end
