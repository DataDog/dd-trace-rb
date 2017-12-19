require 'contrib/sinatra/tracer_test_base'
require 'contrib/sinatra/first_test_app'
require 'contrib/sinatra/second_test_app'

class MultiAppTest < TracerTestBase
  def app
    @use_multi_app ? multi_app : single_app
  end

  def multi_app
    Rack::Builder.new do
      map '/one' do
        run FirstTestApp
      end

      map '/two' do
        run SecondTestApp
      end
    end.to_app
  end

  def single_app
    FirstTestApp
  end

  def setup
    @writer = FauxWriter.new
    FirstTestApp.set :datadog_test_writer, @writer
    SecondTestApp.set :datadog_test_writer, @writer

    tracer = Datadog::Tracer.new(writer: @writer, enabled: true)
    Datadog.configuration[:sinatra][:tracer] = tracer

    super
  end

  def teardown
    disable_script_names!
  end

  def enable_script_names!
    Datadog.configuration[:sinatra][:resource_script_names] = true
  end

  def disable_script_names!
    Datadog.configuration[:sinatra][:resource_script_names] = false
  end

  # Test for when a single, normal app is setup.
  # script_name is ''
  # (To make sure we aren't breaking normal Sinatra apps.)
  def test_resource_name_without_script_name
    @use_multi_app = false
    enable_script_names!

    get '/endpoint'

    spans = @writer.spans.select { |s| s.name == 'sinatra.request' }
    assert_equal(1, spans.length)

    spans.first.tap do |span|
      assert_equal('GET /endpoint', span.resource)
    end
  end

  # Test for when a multi-app is setup.
  # script_name is the sub-app's base prefix.
  # e.g. '/one' in this example.
  # (To make sure we aren't adding script names when disabled.)
  def test_resource_name_with_script_name_disabled
    @use_multi_app = true
    disable_script_names!

    get '/one/endpoint'

    spans = @writer.spans.select { |s| s.name == 'sinatra.request' }
    assert_equal(1, spans.length)

    spans.first.tap do |span|
      assert_equal('GET /endpoint', span.resource)
    end
  end

  # Test for when a multi-app is setup.
  # script_name is the sub-app's base prefix.
  # e.g. '/one' and '/two' in this example.
  # (To make sure we are adding script names when enabled.)
  def test_resource_name_with_script_name
    @use_multi_app = true
    enable_script_names!

    get '/one/endpoint'
    get '/two/endpoint'

    spans = @writer.spans.select { |s| s.name == 'sinatra.request' }
    assert_equal(2, spans.length)

    spans.first.tap do |span|
      assert_equal('GET /one/endpoint', span.resource)
    end

    spans.last.tap do |span|
      assert_equal('GET /two/endpoint', span.resource)
    end
  end
end
