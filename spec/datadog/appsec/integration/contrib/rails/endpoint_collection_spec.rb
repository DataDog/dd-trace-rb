# frozen_string_literal: true

require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/appsec/spec_helper'

require 'rack/test'
require 'action_controller/railtie'

require 'datadog/tracing'
require 'datadog/appsec'

RSpec.describe 'Rails Endpoint Collection' do
  include Rack::Test::Methods

  before do
    app = Class.new(Rails::Application) do
      config.root = __dir__
      config.secret_key_base = 'test-secret-key-base'
      config.action_dispatch.show_exceptions = :rescuable
      config.hosts.clear
      config.eager_load = false
      config.consider_all_requests_local = true
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

      c.remote.enabled = false
    end

    allow(Datadog::AppSec.telemetry).to receive(:app_endpoints_loaded)

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
    allow(Datadog::AppSec.telemetry).to receive(:app_endpoints_loaded).and_raise(StandardError)

    ActiveSupport.run_load_hooks(:after_routes_loaded, Rails.application)
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
        }
      )
    end
  end
end
