require('contrib/sinatra/tracer_test_base')
require('contrib/sinatra/first_test_app')
require('contrib/sinatra/second_test_app')
class MultiAppTest < TracerTestBase
  def app
    @use_multi_app ? multi_app : single_app
  end

  def multi_app
    Rack::Builder.new do
      map('/one') { run(FirstTestApp) }
      map('/two') { run(SecondTestApp) }
    end.to_app
  end

  def single_app
    FirstTestApp
  end
  before do
    @writer = FauxWriter.new
    FirstTestApp.set(:datadog_test_writer, @writer)
    SecondTestApp.set(:datadog_test_writer, @writer)
    tracer = Datadog::Tracer.new(writer: @writer, enabled: true)
    Datadog.configuration[:sinatra][:tracer] = tracer
    super
  end
  after { disable_script_names! }
  def enable_script_names!
    Datadog.configuration[:sinatra][:resource_script_names] = true
  end

  def disable_script_names!
    Datadog.configuration[:sinatra][:resource_script_names] = false
  end
  it('resource name without script name') do
    @use_multi_app = false
    enable_script_names!
    get('/endpoint')
    spans = @writer.spans.select { |s| (s.name == 'sinatra.request') }
    expect(spans.length).to(eq(1))
    spans.first.tap { |span| expect(span.resource).to(eq('GET /endpoint')) }
  end
  it('resource name with script name disabled') do
    @use_multi_app = true
    disable_script_names!
    get('/one/endpoint')
    spans = @writer.spans.select { |s| (s.name == 'sinatra.request') }
    expect(spans.length).to(eq(1))
    spans.first.tap { |span| expect(span.resource).to(eq('GET /endpoint')) }
  end
  it('resource name with script name') do
    @use_multi_app = true
    enable_script_names!
    get('/one/endpoint')
    get('/two/endpoint')
    spans = @writer.spans.select { |s| (s.name == 'sinatra.request') }
    expect(spans.length).to(eq(2))
    spans.first.tap { |span| expect(span.resource).to(eq('GET /one/endpoint')) }
    spans.last.tap { |span| expect(span.resource).to(eq('GET /two/endpoint')) }
  end
end
