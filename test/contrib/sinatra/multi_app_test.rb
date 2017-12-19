require 'contrib/sinatra/tracer_test_base'
require 'contrib/sinatra/first_test_app'
require 'contrib/sinatra/second_test_app'

class MultiAppTest < TracerTestBase
  def app
    Rack::Builder.new do
      map '/one' do
        run FirstTestApp
      end

      map '/two' do
        run SecondTestApp
      end
    end.to_app
  end

  def setup
    @writer = FauxWriter.new()
    FirstTestApp.set :datadog_test_writer, @writer
    SecondTestApp.set :datadog_test_writer, @writer

    tracer = Datadog::Tracer.new(writer: @writer, enabled: true)
    Datadog.configuration[:sinatra][:tracer] = tracer

    super
  end

  def test_resource_name_without_script_name
    first_path = '/one/endpoint'
    get first_path, {}, 'SCRIPT_NAME' => ''

    spans = @writer.spans.select { |s| s.name == 'sinatra.request' }
    assert_equal(1, spans.length)

    spans.first.tap do |span|
      assert_equal("GET #{first_path}", span.resource)
    end
  end

  def test_resource_name_with_script_name
    first_path = '/one/endpoint'
    first_script = '/foo'
    get first_path, {}, 'SCRIPT_NAME' => first_script

    second_path = '/two/endpoint'
    second_script = '/bar'
    get second_path, {}, 'SCRIPT_NAME' => second_script

    spans = @writer.spans.select { |s| s.name == 'sinatra.request' }
    assert_equal(2, spans.length)

    spans.last.tap do |span|
      assert_equal("GET #{first_script}#{first_path}", span.resource)
    end

    spans.first.tap do |span|
      assert_equal("GET #{second_script}#{second_path}", span.resource)
    end
  end
end
