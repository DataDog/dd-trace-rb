require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/action_pack/action_dispatch/instrumentation'

require 'action_pack'
require 'action_controller/railtie'
require 'action_view/railtie'
require 'rails/test_unit/railtie'

require 'spec/datadog/tracing/contrib/rails/support/configuration'
require 'spec/datadog/tracing/contrib/rails/support/application'

RSpec.describe 'Datadog::Tracing::Contrib::ActionPack::ActionDispatch::Journey::Router',
  execute_in_fork: ::ActionPack.version.segments[0] >= 8 do
    let(:no_db) { true }

    include Rack::Test::Methods

    include_context 'Rails test application'

    after do
      Datadog.configuration.tracing[:action_pack].reset!
      Datadog.registry[:rack].reset_configuration!
      Datadog.configuration.tracing.reset!
      Datadog.configuration.appsec.reset!
    end

    describe '#find_routes' do
      before do
        stub_const('AuthEngine', Module.new)

        stub_const(
          'AuthEngine::TokensController',
          Class.new(ActionController::Base) do
            def create
              head :ok
            end
          end
        )

        auth_engine = stub_const(
          'AuthEngine::Engine',
          Class.new(::Rails::Engine) do
            isolate_namespace AuthEngine
          end
        )

        auth_engine.routes.append do
          get '/sign-in' => 'tokens#create'
        end

        rack_status_app = stub_const(
          'RackStatusApp',
          Class.new do
            def call(_env)
              [200, {'Content-Type' => 'text/plain'}, ['OK']]
            end
          end
        )

        stub_const(
          'Api::UsersController',
          Class.new(ActionController::Base) do
            def show
              head :ok
            end
          end
        )

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

        rails_test_application.instance.routes.append do
          namespace :api, defaults: {format: :json} do
            resources :users, only: %i[show]

            mount auth_engine => '/auth'
            mount rack_status_app.new => '/status'
          end

          get '/items/:id', to: 'items#by_id', id: /\d+/
          get '/items/:slug', to: 'items#by_slug', id: /(\w-)+/

          get 'books(/:category)', to: 'books#index'
          get 'books/*section/:title', to: 'books#show'
        end
      end

      context 'with default configuration' do
        before do
          Datadog.configure do |c|
            c.tracing.instrument :rack
            c.tracing.instrument :action_pack
          end

          clear_traces!
        end

        describe 'http.route tag' do
          it 'is set correctly when requesting a known route' do
            get '/api/users/1'

            request_span = spans.first

            expect(last_response).to be_ok
            expect(request_span.name).to eq('rack.request')
            expect(request_span.tags.fetch('http.route')).to eq('/api/users/:id')
            expect(request_span.tags).not_to have_key('http.route.path')
          end

          it 'is set correctly for ambiguous route with constraints' do
            get '/items/1'

            request_span = spans.first

            expect(last_response).to be_ok
            expect(request_span.name).to eq('rack.request')
            expect(request_span.tags.fetch('http.route')).to eq('/items/:id')
            expect(request_span.tags).not_to have_key('http.route.path')
          end

          it 'is set correctly for ambiguous route with constraints, case two' do
            get '/items/something'

            request_span = spans.first

            expect(last_response).to be_ok
            expect(request_span.name).to eq('rack.request')
            expect(request_span.tags.fetch('http.route')).to eq('/items/:slug')
            expect(request_span.tags).not_to have_key('http.route.path')
          end

          it 'is set correctly for routes with globbing' do
            get 'books/some/section/title'

            request_span = spans.first

            expect(last_response).to be_ok
            expect(request_span.name).to eq('rack.request')
            expect(request_span.tags.fetch('http.route')).to eq('/books/*section/:title')
            expect(request_span.tags).not_to have_key('http.route.path')
          end

          it 'is set correctly for routes with optional parameter' do
            get 'books/some-category'

            request_span = spans.first

            expect(last_response).to be_ok
            expect(request_span.name).to eq('rack.request')
            expect(request_span.tags.fetch('http.route')).to eq('/books(/:category)')
            expect(request_span.tags).not_to have_key('http.route.path')
          end

          it 'is set correctly for rails engine routes' do
            get '/api/auth/sign-in'

            request_span = spans.first

            expect(last_response).to be_ok
            expect(request_span.name).to eq('rack.request')
            expect(request_span.tags.fetch('http.route')).to eq('/api/auth/sign-in')
            expect(request_span.tags).not_to have_key('http.route.path')
          end

          it 'is set correctly for a route to a mounted rack app' do
            get '/api/status/some/path/123'

            request_span = spans.first

            expect(last_response).to be_ok
            expect(request_span.name).to eq('rack.request')
            expect(request_span.tags.fetch('http.route')).to eq('/api/status')
            expect(request_span.tags).not_to have_key('http.route.path')
          end

          it 'is not set when requesting an unknown route' do
            get '/nope'

            request_span = spans.first

            expect(last_response).to be_not_found
            expect(request_span.name).to eq('rack.request')
            expect(request_span.tags).not_to have_key('http.route')
            expect(request_span.tags).not_to have_key('http.route.path')
          end
        end

        describe 'http.endpoint tag' do
          context 'when resource_renaming.enabled is disabled by default and appsec is enabled' do
            before do
              Datadog.configuration.appsec.enabled = true
              Datadog.configuration.tracing.resource_renaming.reset!
            end

            it 'reports http.endpoint for rails routes' do
              get '/api/users/1'

              request_span = spans.first

              expect(last_response).to be_ok
              expect(request_span.name).to eq('rack.request')
              expect(request_span.tags.fetch('http.endpoint')).to eq('/api/users/:id')
            end
          end

          context 'when resource_renaming.enabled is explicitly set to false and appsec is enabled' do
            before do
              Datadog.configuration.appsec.enabled = true
              Datadog.configuration.tracing.resource_renaming.enabled = false
            end

            it 'does not report http.endpoint for rails routes' do
              get '/api/users/1'

              request_span = spans.first

              expect(last_response).to be_ok
              expect(request_span.name).to eq('rack.request')
              expect(request_span.tags).not_to have_key('http.endpoint')
            end
          end

          context 'when resource_renaming.enabled is set to true' do
            before do
              Datadog.configuration.tracing.resource_renaming.enabled = true
            end

            context 'when resource_renaming.always_simplified_endpoint is set to false' do
              before do
                Datadog.configuration.tracing.resource_renaming.always_simplified_endpoint = false
              end

              it 'is set correctly when requesting a known route' do
                get '/api/users/1'

                request_span = spans.first

                expect(last_response).to be_ok
                expect(request_span.name).to eq('rack.request')
                expect(request_span.tags.fetch('http.endpoint')).to eq('/api/users/:id')
              end

              it 'is set correctly for ambiguous route with constraints' do
                get '/items/1'

                request_span = spans.first

                expect(last_response).to be_ok
                expect(request_span.name).to eq('rack.request')
                expect(request_span.tags.fetch('http.endpoint')).to eq('/items/:id')
              end

              it 'is set correctly for routes with globbing' do
                get 'books/some/section/title'

                request_span = spans.first

                expect(last_response).to be_ok
                expect(request_span.name).to eq('rack.request')
                expect(request_span.tags.fetch('http.endpoint')).to eq('/books/*section/:title')
              end

              it 'is set correctly for routes with optional parameter' do
                get 'books/some-category'

                request_span = spans.first

                expect(last_response).to be_ok
                expect(request_span.name).to eq('rack.request')
                expect(request_span.tags.fetch('http.endpoint')).to eq('/books(/:category)')
              end

              it 'is set correctly for rails engine routes' do
                get '/api/auth/sign-in'

                request_span = spans.first

                expect(last_response).to be_ok
                expect(request_span.name).to eq('rack.request')
                expect(request_span.tags.fetch('http.endpoint')).to eq('/api/auth/sign-in')
              end

              it 'is set using infered route for routes to a mounted rack app' do
                get '/api/status/some/path/123'

                request_span = spans.first

                expect(last_response).to be_ok
                expect(request_span.name).to eq('rack.request')
                expect(request_span.tags.fetch('http.endpoint')).to eq('/api/status/some/path/{param:int}')
              end

              it 'is not set when requesting an unknown route' do
                get '/nope'

                request_span = spans.first

                expect(last_response).to be_not_found
                expect(request_span.name).to eq('rack.request')
                expect(request_span.tags).not_to have_key('http.endpoint')
              end
            end

            context 'when tracing.resource_renaming.always_simplified_endpoint is set to true' do
              before do
                Datadog.configuration.tracing.resource_renaming.always_simplified_endpoint = true
              end

              it 'infers http.endpoint without using http.route tag value' do
                get '/api/users/1'

                request_span = spans.first

                expect(last_response).to be_ok
                expect(request_span.name).to eq('rack.request')
                expect(request_span.tags.fetch('http.endpoint')).to eq('/api/users/{param:int}')
              end
            end
          end
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
