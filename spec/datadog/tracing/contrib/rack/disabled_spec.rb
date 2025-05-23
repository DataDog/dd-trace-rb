require 'datadog/tracing/contrib/support/spec_helper'
require 'rack/test'
require 'rack'
require 'datadog'
require 'datadog/tracing/contrib/rack/middlewares'

RSpec.describe 'Rack integration tests' do
  include Rack::Test::Methods

  before do
    Datadog.configure do |c|
      c.tracing.enabled = false
      c.tracing.instrument :rack, distributed_tracing: false
    end
  end

  after do
    Datadog.registry[:rack].reset_configuration!
    Datadog.configuration.reset!
  end

  context 'for an application' do
    let(:app) do
      Rack::Builder.new do
        use Datadog::Tracing::Contrib::Rack::TraceMiddleware
        map '/success/' do
          run(proc { |_env| [200, { 'Content-Type' => 'text/html' }, ['OK']] })
        end
      end.to_app
    end

    context 'with a basic route' do
      describe 'GET request' do
        it do
          response = get 'success'

          expect(response).to be_ok

          expect(spans).to have(0).items
        end
      end
    end
  end
end
