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

    stub_const('RailsTest::EndpointCollectionApplication', app)

    Datadog.configure do |c|
      c.tracing.enabled = true
      c.appsec.enabled = true
      c.appsec.api_security.endpoint_collection.enabled = true
      c.appsec.instrument :rails

      c.remote.enabled = false
    end

    allow(Datadog::AppSec.telemetry).to receive(:app_endpoints_loaded)

    app.initialize!

    app.routes.draw do
      resources :products

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

    ActiveSupport::Dependencies.clear if Rails.application
    ActiveSupport::Dependencies.autoload_paths = []
    ActiveSupport::Dependencies.autoload_once_paths = []
    ActiveSupport::Dependencies._eager_load_paths = Set.new
    ActiveSupport::Dependencies._autoloaded_tracked_classes = Set.new

    Rails::Railtie::Configuration.class_variable_set(:@@eager_load_namespaces, nil)
    Rails::Railtie::Configuration.class_variable_set(:@@watchable_files, nil)
    Rails::Railtie::Configuration.class_variable_set(:@@watchable_dirs, nil)
    Rails::Railtie::Configuration.class_variable_set(:@@app_generators, nil)
    Rails::Railtie::Configuration.class_variable_set(:@@to_prepare_blocks, nil)

    Rails.app_class = nil
    Rails.cache = nil
  end

  it 'reports routes via telemetry' do
    expect(Datadog::AppSec.telemetry).to have_received(:app_endpoints_loaded).with(array_including([
      {
        type: 'REST',
        resource_name: 'GET /products',
        operation_name: 'http.request',
        method: 'GET',
        path: '/products'
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
        resource_name: 'DELETE /products/:id',
        operation_name: 'http.request',
        method: 'DELETE',
        path: '/products/:id'
      },
      {
        type: 'REST',
        resource_name: '* /search',
        operation_name: 'http.request',
        method: '*',
        path: '/search'
      }
    ]))
  end
end
