require_relative 'helpers'

class ResourceNameTest < Minitest::Test
  include Rack::Test::Methods
  attr_reader :app

  def setup
    @previous_configuration = Datadog.configuration[:rack].to_h
    @tracer = get_test_tracer
    @app = Rack::Builder.new do
      use Datadog::Contrib::Rack::TraceMiddleware
      use AuthMiddleware
      run BottomMiddleware.new
    end.to_app

    remove_patch!(:rack)
    Datadog.registry[:rack].instance_variable_set('@middleware_patched', false)
    Datadog.configuration.use(
      :rack,
      middleware_names: true,
      tracer: @tracer,
      application: @app
    )
  end

  def teardown
    Datadog.configuration.use(:rack, @previous_configuration)
  end

  def test_resource_name_full_chain
    get '/', {}, 'HTTP_AUTH_TOKEN' => '1234'

    spans = @tracer.writer.spans
    assert(last_response.ok?)
    assert_equal(1, spans.length)
    assert_match(/BottomMiddleware#GET/, spans[0].resource)
  end

  def test_resource_name_short_circuited_request
    get '/', {}, 'HTTP_AUTH_TOKEN' => 'Wrong'

    spans = @tracer.writer.spans
    refute(last_response.ok?)
    assert_equal(1, spans.length)
    assert_match(/AuthMiddleware#GET/, spans[0].resource)
  end

  class AuthMiddleware
    def initialize(app)
      @app = app
    end

    def call(env)
      return [401, {}, []] if env['HTTP_AUTH_TOKEN'] != '1234'

      @app.call(env)
    end
  end

  class BottomMiddleware
    def call(_)
      [200, {}, []]
    end
  end
end
