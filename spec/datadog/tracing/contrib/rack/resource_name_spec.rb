require 'datadog/tracing/contrib/support/spec_helper'
require 'rack/test'

require 'rack'
require 'ddtrace'
require 'datadog/tracing/contrib/rack/middlewares'

RSpec.describe 'Rack integration with other middleware' do
  include Rack::Test::Methods

  let(:rack_options) do
    {
      application: app,
      middleware_names: true
    }
  end

  before do
    # Undo the Rack middleware name patch
    Datadog.registry[:rack].patcher::PATCHERS.each do |patcher|
      remove_patch!(patcher)
    end

    Datadog.configure do |c|
      c.tracing.instrument :rack, rack_options
    end
  end

  after do
    Datadog.registry[:rack].reset_configuration!
  end

  shared_context 'app with middleware' do
    let(:app) do
      auth_mw = auth_middleware
      bottom_mw = bottom_middleware

      Rack::Builder.new do
        use Datadog::Tracing::Contrib::Rack::TraceMiddleware
        use auth_mw
        run bottom_mw.new
      end.to_app
    end

    let(:auth_middleware) do
      stub_const(
        'AuthMiddleware',
        Class.new do
          def initialize(app)
            @app = app
          end

          def call(env)
            return [401, {}, []] if env['HTTP_AUTH_TOKEN'] != '1234'

            @app.call(env)
          end
        end
      )
    end

    let(:bottom_middleware) do
      stub_const(
        'BottomMiddleware',
        Class.new do
          def call(_)
            [200, {}, []]
          end
        end
      )
    end
  end

  context 'which receives an incoming HTTP request' do
    subject(:response) { get '/', {}, headers }

    let(:headers) { {} }

    include_context 'app with middleware'

    context 'which runs the full stack' do
      let(:headers) { { 'HTTP_AUTH_TOKEN' => '1234' } }

      it 'creates a span with the bottom middleware as a resource name' do
        is_expected.to be_ok
        expect(spans).to have(1).items
        expect(span.resource).to match(/BottomMiddleware#GET/)
      end
    end

    context 'which stops part way down the stack' do
      let(:headers) { { 'HTTP_AUTH_TOKEN' => 'foobar' } }

      it 'creates a span with the deepest middleware reached as a resource name' do
        expect(response.status).to eq(401)
        expect(spans).to have(1).items
        expect(span.resource).to match(/AuthMiddleware#GET/)
      end
    end
  end
end
