require 'ddtrace'
require 'rack'
require 'hanami'

RSpec.shared_context 'Hanami test application' do
  let(:build_test_app) do
    module Dummy
      class App < ::Hanami::Application
        configure do
          root __dir__ + '/dummy'

          routes do
            get "/simple_success", to: ->(env) { [200, {}, ["Welcome to Hanami!"]] }
            get '/books', to: "books#index"
            get '/server_error', to: "books#server_error"
          end

          load_paths << ['controllers', 'views']
        end
      end
    end

    Dummy::App
  end

  let(:app) do
    if ENV['TEST_AUTO_INSTRUMENT'] == 'true'
      require 'ddtrace/auto_instrument'
    else
      require 'datadog/tracing/contrib/hanami/plugin'
    end
    Datadog.configure do |c|
      c.tracing.instrument :hanami
    end

    allow_any_instance_of(::Hanami::Environment).to receive(:root).and_return(
      Pathname.new(__dir__ + '/dummy')
    )
    test_app = build_test_app

    ::Hanami.configure do
      mount test_app, at: '/'
    end

    ::Rack::Builder.new do
      run ::Hanami.app
    end.to_app
  end

  after(:each) do
    ::Hanami::Components.release
  end
end
