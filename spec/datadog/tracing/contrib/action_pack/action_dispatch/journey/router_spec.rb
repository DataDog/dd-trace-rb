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
        post '/sign-in/(:expires_in)' => 'tokens#create'
      end

      auth_engine = engine

      rails_test_application.instance.routes.append do
        namespace :api, defaults: { format: :json } do
          resources :users, only: %i[show]

          mount auth_engine => '/auth'
        end

        get '/items/:id', to: 'items#by_id', id: /\d+/
        get '/items/:slug', to: 'items#by_slug', id: /(\w-)+/

        get 'books/*section/:title', to: 'books#show'
      end
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

        rack_trace = traces.first

        expect(rack_trace.name).to eq('rack.request')
        expect(rack_trace.send(:meta).fetch('http.route')).to eq('/api/users/:id')
        expect(rack_trace.send(:meta)).not_to have_key('http.route.path')
      end

      it 'sets http.route correctly for ambiguous route with constraints' do
        get '/items/1'

        rack_trace = traces.first

        expect(rack_trace.name).to eq('rack.request')
        expect(rack_trace.send(:meta).fetch('http.route')).to eq('/items/:id')
        expect(rack_trace.send(:meta)).not_to have_key('http.route.path')
      end

      it 'sets http.route correctly for ambiguous route with constraints, case two' do
        get '/items/something'

        rack_trace = traces.first

        expect(rack_trace.name).to eq('rack.request')
        expect(rack_trace.send(:meta).fetch('http.route')).to eq('/items/:slug')
        expect(rack_trace.send(:meta)).not_to have_key('http.route.path')
      end

      it 'sets http.route correctly for routes with globbing' do
        get 'books/some/section/title'

        rack_trace = traces.first

        expect(rack_trace.name).to eq('rack.request')
        expect(rack_trace.send(:meta).fetch('http.route')).to eq('/books/*section/:title')
        expect(rack_trace.send(:meta)).not_to have_key('http.route.path')
      end

      it 'sets http.route and http.route.path for rails engine routes' do
        post '/api/auth/sign-in'

        rack_trace = traces.first

        expect(rack_trace.name).to eq('rack.request')
        expect(rack_trace.send(:meta).fetch('http.route')).to eq('/sign-in(/:expires_in)')
        expect(rack_trace.send(:meta).fetch('http.route.path')).to eq('/api/auth')
      end

      it 'does not set http.route when requesting an unknown route' do
        get '/nope'

        rack_trace = traces.first

        expect(rack_trace.name).to eq('rack.request')
        expect(rack_trace.send(:meta)).not_to have_key('http.route')
        expect(rack_trace.send(:meta)).not_to have_key('http.route.path')
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
