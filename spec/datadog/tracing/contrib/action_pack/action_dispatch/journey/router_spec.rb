require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/action_pack/action_dispatch/instrumentation'

require 'action_pack'
require 'action_controller/railtie'
require 'action_view/railtie'
require 'rails/test_unit/railtie'

require 'spec/datadog/tracing/contrib/rails/support/configuration'
require 'spec/datadog/tracing/contrib/rails/support/application'

RSpec.describe 'Datadog::Tracing::Contrib::ActionPack::ActionDispatch::Journey::Router' do
  let(:no_db) { true }

  include Rack::Test::Methods
  include_context 'Rails test application'

  after do
    Datadog.configuration.tracing[:action_pack].reset!
    Datadog.registry[:rack].reset_configuration!
  end

  describe '#find_routes' do
    before do
      engine.routes.append do
        get '/sign-in' => 'tokens#create'
      end

      auth_engine = engine
      rack_status_app = rack_app.new

      rails_test_application.instance.routes.append do
        namespace :api, defaults: { format: :json } do
          resources :users, only: %i[show]

          mount auth_engine => '/auth'

          match '/status', to: rack_status_app, via: :get
        end

        get '/items/:id', to: 'items#by_id', id: /\d+/
        get '/items/:slug', to: 'items#by_slug', id: /(\w-)+/

        get 'books(/:category)', to: 'books#index'
        get 'books/*section/:title', to: 'books#show'
      end
    end

    let(:rack_app) do
      stub_const(
        'RackStatusApp',
        Class.new do
          def call(_env)
            [200, { 'Content-Type' => 'text/plain' }, ['OK']]
          end
        end
      )
    end

    let(:controllers) { [users_controller, items_controller, books_controller] }

    let(:users_controller) do
      stub_const(
        'Api::UsersController',
        Class.new(ActionController::Base) do
          def show
            head :ok
          end
        end
      )
    end

    let(:items_controller) do
      stub_const(
        'ItemsController',
        Class.new(ActionController::Base) do
          def by_id
            head :ok
          end

          def by_slug
            head :ok
          end
        end
      )
    end

    let(:books_controller) do
      stub_const(
        'BooksController',
        Class.new(ActionController::Base) do
          def index
            head :ok
          end

          def show
            head :ok
          end
        end
      )
    end

    let(:status_controller) do
      stub_const(
        'StatusesController',
        Class.new(ActionController::Base) do
          def show
            head :ok
          end
        end
      )
    end

    let(:engine) do
      stub_const('AuthEngine', Module.new)

      stub_const(
        'AuthEngine::TokensController',
        Class.new(ActionController::Base) do
          def create
            head :ok
          end
        end
      )

      stub_const(
        'AuthEngine::Engine',
        Class.new(::Rails::Engine) do
          isolate_namespace AuthEngine
        end
      )
    end

    context 'with default configuration' do
      before do
        Datadog.configure do |c|
          c.tracing.instrument :rack
          c.tracing.instrument :action_pack
        end

        clear_traces!
      end

      it 'sets http.route when requesting a known route' do
        get '/api/users/1'

        request_span = spans.first

        expect(last_response).to be_ok
        expect(request_span.name).to eq('rack.request')
        expect(request_span.tags.fetch('http.route')).to eq('/api/users/:id')
        expect(request_span.tags).not_to have_key('http.route.path')
      end

      it 'sets http.route correctly for ambiguous route with constraints' do
        get '/items/1'

        request_span = spans.first

        expect(last_response).to be_ok
        expect(request_span.name).to eq('rack.request')
        expect(request_span.tags.fetch('http.route')).to eq('/items/:id')
        expect(request_span.tags).not_to have_key('http.route.path')
      end

      it 'sets http.route correctly for ambiguous route with constraints, case two' do
        get '/items/something'

        request_span = spans.first

        expect(last_response).to be_ok
        expect(request_span.name).to eq('rack.request')
        expect(request_span.tags.fetch('http.route')).to eq('/items/:slug')
        expect(request_span.tags).not_to have_key('http.route.path')
      end

      it 'sets http.route correctly for routes with globbing' do
        get 'books/some/section/title'

        request_span = spans.first

        expect(last_response).to be_ok
        expect(request_span.name).to eq('rack.request')
        expect(request_span.tags.fetch('http.route')).to eq('/books/*section/:title')
        expect(request_span.tags).not_to have_key('http.route.path')
      end

      it 'sets http.route correctly for routes with optional parameter' do
        get 'books/some-category'

        request_span = spans.first

        expect(last_response).to be_ok
        expect(request_span.name).to eq('rack.request')
        expect(request_span.tags.fetch('http.route')).to eq('/books(/:category)')
        expect(request_span.tags).not_to have_key('http.route.path')
      end

      it 'sets http.route and http.route.path for rails engine routes' do
        get '/api/auth/sign-in'

        request_span = spans.first

        expect(last_response).to be_ok
        expect(request_span.name).to eq('rack.request')
        expect(request_span.tags.fetch('http.route')).to eq('/api/auth/sign-in')
        expect(request_span.tags).not_to have_key('http.route.path')
      end

      it 'sets http.route for a route to a rack app' do
        get '/api/status'

        request_span = spans.first

        expect(last_response).to be_ok
        expect(request_span.name).to eq('rack.request')
        expect(request_span.tags.fetch('http.route')).to eq('/api/status')
        expect(request_span.tags).not_to have_key('http.route.path')
      end

      it 'does not set http.route when requesting an unknown route' do
        get '/nope'

        request_span = spans.first

        expect(last_response).to be_not_found
        expect(request_span.name).to eq('rack.request')
        expect(request_span.tags).not_to have_key('http.route')
        expect(request_span.tags).not_to have_key('http.route.path')
      end
    end

    context 'when tracing is disabled' do
      before do
        Datadog.configure do |c|
          c.tracing.enabled = false
        end

        clear_traces!
      end

      it 'does not set http.route' do
        get '/api/users/1'

        expect(traces).to be_empty
      end
    end
  end
end
