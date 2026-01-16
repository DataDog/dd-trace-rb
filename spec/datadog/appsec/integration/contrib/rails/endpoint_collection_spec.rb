# frozen_string_literal: true

require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/appsec/spec_helper'
require 'rack/test'

require 'action_controller/railtie'
require 'active_record'
require 'grape'
require 'sinatra/base'
require 'sqlite3'
require 'devise'

RSpec.describe 'Rails Endpoint Collection' do
  include Rack::Test::Methods
  include Warden::Test::Helpers

  before do
    # TODO: Remove Devise
    # We do not need Devise for this spec, but since Devise pollutes the global namespace,
    # it leads to this test being flaky, since it is run in the same process as other
    # integration tests that use Devise.

    # NOTE: By doing this we are emulating the initial load of the devise rails
    #       engine for every test case. It will install the required middleware.
    #       WARNING: This is a hack!
    Devise.send(:remove_const, :Engine)

    load File.join(Gem.loaded_specs['devise'].full_gem_path, 'lib/devise/rails.rb')

    Devise.warden_config = Warden::Config.new
    Devise.class_variable_set(:@@warden_configured, nil) # rubocop:disable Style/ClassVars
    Devise.configure_warden!

    Devise.setup do |config|
      config.secret_key = 'test-secret-key'

      require 'devise/orm/active_record'

      config.sign_out_via = :delete
      config.responder.error_status = :unprocessable_entity
      config.responder.redirect_status = :see_other
      config.sign_out_all_scopes = false
      config.parent_controller = 'TestApplicationController'
      config.paranoid = true
      config.stretches = 1
      config.password_length = 6..8
      config.http_authenticatable = true
    end

    # app/models
    stub_const('User', Class.new(ActiveRecord::Base)).tap do |klass|
      klass.establish_connection({adapter: 'sqlite3', database: ':memory:'})
      klass.connection.create_table 'users', force: :cascade do |t|
        t.string :username, null: false
        t.string :email, default: '', null: false
        t.string :encrypted_password, default: '', null: false
      end

      klass.class_eval do
        devise :database_authenticatable, :registerable, :validatable
      end

      # prevent internal sql requests from showing up
      klass.count
    end

    stub_const('TestApplicationController', Class.new(ActionController::Base)).class_eval do
    end

    # NOTE: Unfortunately, can't figure out why devise receives 3 times `finalize!`
    #       of the RouteSet patch, hence it's bypassed with below hack.
    #       The order of hacks matters!
    allow(Devise).to receive(:regenerate_helpers!)

    app = Class.new(Rails::Application) do
      config.root = __dir__
      config.secret_key_base = 'test-secret-key-base'
      config.action_dispatch.show_exceptions = :rescuable
      config.hosts.clear
      config.eager_load = false
      config.consider_all_requests_local = true
      # NOTE: For debugging replace with $stdout
      config.logger = Rails.logger = Logger.new(StringIO.new)

      config.file_watcher = Class.new(ActiveSupport::FileUpdateChecker) do
        def initialize(files, dirs = {}, &block)
          dirs = dirs.delete('') if dirs.include?('')

          super
        end
      end
    end

    stub_const('RailsTest::Application', app)

    Datadog.configure do |c|
      c.tracing.enabled = true

      c.appsec.enabled = true
      c.appsec.api_security.endpoint_collection.enabled = true
      c.appsec.instrument :rails
      c.appsec.instrument :devise

      c.remote.enabled = false
    end

    allow(Datadog::AppSec.telemetry).to receive(:app_endpoints_loaded)

    grape_app = Class.new(Grape::API) do
      format :json

      get '/' do
        {message: 'Grape Home'}
      end

      get '/param/:name' do
        route = request.env["datadog.http.route"]
        {
          message: 'Grape Params Endpoint (GET)',
          route: route,
          name: params[:name]
        }
      end

      namespace 'namespaced' do
        get '/param/:name' do
          route = request.env["datadog.http.route"]
          {
            message: 'Grape Params Endpoint (GET)',
            route: route,
            name: params[:name]
          }
        end
      end
    end

    sinatra_app = Class.new(Sinatra::Base) do
      get '/' do
        ''
      end

      get '/param/:name' do
        ''
      end
    end

    # app.initialize!
    app.routes.draw do
      resources :products

      resources :users, only: %i[index show] do
        resources :photos, only: %i[index create destroy]
      end

      get '/photos(/:id)', to: 'photos#display'

      root to: 'home#show'

      get '/job-queue', to: 'job_queue#index', constraints: {subdomain: 'tech-stuff'}

      namespace :admin do
        get '/stats', to: 'statistics#index'

        post '/sign-in', to: 'sessions#create'
        delete '/sign-out', to: 'sessions#destroy'
      end

      match '/search', to: 'search#index', via: :all
      match '/multi-method-route', to: 'multi_method#index', via: %i[get post]

      mount grape_app => '/grape'
      mount sinatra_app => '/sinatra'
    end

    allow(Rails).to receive(:application).and_return(app)

    allow_any_instance_of(Datadog::Tracing::Transport::HTTP::Client).to receive(:send_request)
    allow_any_instance_of(Datadog::Tracing::Transport::Traces::Transport).to receive(:native_events_supported?)
  end

  after do
    clear_traces!

    Datadog.configuration.reset!
    Datadog.registry[:rack].reset_configuration!

    Datadog::AppSec::RateLimiter.reset!
    Datadog::AppSec::APISecurity::Sampler.reset!
  end

  before(:each) do
    # reset guard that only allows routes to be reported once
    Datadog::AppSec::Contrib::Rails::Patcher::GUARD_ROUTES_REPORTING_ONCE_PER_APP[Rails.application]
      .instance_variable_set(:@ran_once, false)
  end

  it 'rescues exceptions' do
    expect(Datadog::AppSec.telemetry).to receive(:app_endpoints_loaded).and_raise(StandardError)

    ActiveSupport.run_load_hooks(:after_routes_loaded, Rails.application)
  end

  it 'does not raise an error when AppSec.telemetry is nil' do
    allow(Datadog::AppSec).to receive(:telemetry).and_return(nil)

    expect do
      ActiveSupport.run_load_hooks(:after_routes_loaded, Rails.application)
    end.not_to raise_error
  end

  it 'reports routes via telemetry' do
    ActiveSupport.run_load_hooks(:after_routes_loaded, Rails.application)

    expect(Datadog::AppSec.telemetry).to have_received(:app_endpoints_loaded) do |arg|
      expect(arg.to_a).to contain_exactly(
        {
          type: 'REST',
          resource_name: 'GET /',
          operation_name: 'http.request',
          method: 'GET',
          path: '/'
        },
        {
          type: 'REST',
          resource_name: 'GET /products',
          operation_name: 'http.request',
          method: 'GET',
          path: '/products'
        },
        {
          type: 'REST',
          resource_name: 'GET /products/new',
          operation_name: 'http.request',
          method: 'GET',
          path: '/products/new'
        },
        {
          type: 'REST',
          resource_name: 'POST /products',
          operation_name: 'http.request',
          method: 'POST',
          path: '/products'
        },
        {
          type: 'REST',
          resource_name: 'GET /products/:id',
          operation_name: 'http.request',
          method: 'GET',
          path: '/products/:id'
        },
        {
          type: 'REST',
          resource_name: 'GET /products/:id/edit',
          operation_name: 'http.request',
          method: 'GET',
          path: '/products/:id/edit'
        },
        {
          type: 'REST',
          resource_name: 'PATCH /products/:id',
          operation_name: 'http.request',
          method: 'PATCH',
          path: '/products/:id'
        },
        {
          type: 'REST',
          resource_name: 'PUT /products/:id',
          operation_name: 'http.request',
          method: 'PUT',
          path: '/products/:id'
        },
        {
          type: 'REST',
          resource_name: 'DELETE /products/:id',
          operation_name: 'http.request',
          method: 'DELETE',
          path: '/products/:id'
        },
        {
          type: 'REST',
          resource_name: 'GET /users',
          operation_name: 'http.request',
          method: 'GET',
          path: '/users'
        },
        {
          type: 'REST',
          resource_name: 'GET /users/:id',
          operation_name: 'http.request',
          method: 'GET',
          path: '/users/:id'
        },
        {
          type: 'REST',
          resource_name: 'GET /users/:user_id/photos',
          operation_name: 'http.request',
          method: 'GET',
          path: '/users/:user_id/photos'
        },
        {
          type: 'REST',
          resource_name: 'POST /users/:user_id/photos',
          operation_name: 'http.request',
          method: 'POST',
          path: '/users/:user_id/photos'
        },
        {
          type: 'REST',
          resource_name: 'DELETE /users/:user_id/photos/:id',
          operation_name: 'http.request',
          method: 'DELETE',
          path: '/users/:user_id/photos/:id'
        },
        {
          type: 'REST',
          resource_name: 'GET /photos(/:id)',
          operation_name: 'http.request',
          method: 'GET',
          path: '/photos(/:id)'
        },
        {
          type: 'REST',
          resource_name: 'GET /admin/stats',
          operation_name: 'http.request',
          method: 'GET',
          path: '/admin/stats'
        },
        {
          type: 'REST',
          resource_name: 'POST /admin/sign-in',
          operation_name: 'http.request',
          method: 'POST',
          path: '/admin/sign-in'
        },
        {
          type: 'REST',
          resource_name: 'DELETE /admin/sign-out',
          operation_name: 'http.request',
          method: 'DELETE',
          path: '/admin/sign-out'
        },
        {
          type: 'REST',
          resource_name: 'GET /job-queue',
          operation_name: 'http.request',
          method: 'GET',
          path: '/job-queue'
        },
        {
          type: 'REST',
          resource_name: '* /search',
          operation_name: 'http.request',
          method: '*',
          path: '/search'
        },
        {
          type: 'REST',
          resource_name: 'GET /multi-method-route',
          operation_name: 'http.request',
          method: 'GET',
          path: '/multi-method-route'
        },
        {
          type: 'REST',
          resource_name: 'POST /multi-method-route',
          operation_name: 'http.request',
          method: 'POST',
          path: '/multi-method-route'
        },
        {
          type: 'REST',
          resource_name: 'GET /grape/',
          operation_name: 'http.request',
          method: 'GET',
          path: '/grape/'
        },
        {
          type: 'REST',
          resource_name: 'GET /grape/param/:name',
          operation_name: 'http.request',
          method: 'GET',
          path: '/grape/param/:name'
        },
        {
          type: 'REST',
          resource_name: 'GET /grape/namespaced/param/:name',
          operation_name: 'http.request',
          method: 'GET',
          path: '/grape/namespaced/param/:name'
        },
        {
          type: 'REST',
          resource_name: 'GET /sinatra/',
          operation_name: 'http.request',
          method: 'GET',
          path: '/sinatra/'
        },
        {
          type: 'REST',
          resource_name: 'GET /sinatra/param/{name}',
          operation_name: 'http.request',
          method: 'GET',
          path: '/sinatra/param/{name}'
        }
      )
    end
  end
end
