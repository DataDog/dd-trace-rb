# frozen_string_literal: true

require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/appsec/spec_helper'
require 'rack/test'

require 'action_controller/railtie'
require 'sqlite3'
require 'active_record'
require 'datadog/tracing'
require 'datadog/appsec'

RSpec.describe 'Schema extraction for API security' do
  include Rack::Test::Methods

  before do
    stub_const('User', Class.new(ActiveRecord::Base)).tap do |klass|
      klass.establish_connection({adapter: 'sqlite3', database: ':memory:'})

      klass.connection.create_table 'users', force: :cascade do |t|
        t.string :name, null: false
      end

      # prevent internal sql requests from showing up
      klass.count
    end

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

    Datadog.configure do |config|
      config.tracing.enabled = true
      config.tracing.sampler = sampler
      config.apm.tracing.enabled = true
      config.tracing.instrument :rails

      config.appsec.enabled = true
      config.appsec.instrument :rails
      config.appsec.instrument :active_record

      config.appsec.ruleset = {
        rules: [
          {
            id: 'rasp-003-001',
            name: 'SQL Injection',
            tags: {
              type: 'sql_injection',
              category: 'exploit',
              module: 'rasp'
            },
            conditions: [
              {
                operator: 'sqli_detector',
                parameters: {
                  resource: [{address: 'server.db.statement'}],
                  params: [{address: 'server.request.query'}],
                  db_type: [{address: 'server.db.system'}]
                }
              }
            ],
            on_match: ['block']
          }
        ]
      }

      config.remote.enabled = false
    end

    app.initialize!
    app.routes.draw do
      get '/api/users', to: 'api#users'
      get '/api/search', to: 'api#search'
    end

    stub_const('ApiController', Class.new(ActionController::Base)).class_eval do
      def users
        render json: {id: 1, name: 'John', email: 'john@example.com'}
      end

      def search
        users = User.find_by_sql(
          "SELECT * FROM users WHERE name = '#{params[:name]}'"
        )
        render json: users
      end
    end

    allow(Rails).to receive(:application).and_return(app)

    allow_any_instance_of(Datadog::Tracing::Transport::HTTP::Client).to receive(:send_request)
    allow_any_instance_of(Datadog::Tracing::Transport::Traces::Transport).to receive(:native_events_supported?)
      .and_return(true)
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
    Rails::Railtie::Configuration.class_variable_set(:@@app_middleware, nil)

    Rails.app_class = nil
    Rails.cache = nil
  end

  let(:sampler) { instance_double(Datadog::Tracing::Sampling::Sampler, sample!: true) }
  let(:http_service_entry_span) { spans.find { |s| s.name == 'rack.request' } }
  let(:response) { last_response }
  let(:app) { Rails.application }

  context 'when API security is enabled and request is sampled' do
    before do
      Datadog.configure do |config|
        config.appsec.api_security.enabled = true
        config.appsec.api_security.sample_delay = 30
      end

      get('/api/users')
    end

    it 'extracts schema and adds to span tags' do
      expect(response).to be_ok
      expect(http_service_entry_span.tags).to include(
        match(%r{_dd.appsec.s.req.*}),
        match(%r{_dd.appsec.s.res.*})
      )
    end
  end

  context 'when API security is enabled but request is not sampled' do
    before do
      Datadog.configure do |config|
        config.appsec.api_security.enabled = true
        config.appsec.api_security.sample_delay = 30
      end
    end

    context 'when APM sampler rejects the trace' do
      before { get('/api/users') }

      let(:sampler) { instance_double(Datadog::Tracing::Sampling::Sampler, sample!: false) }

      it 'does not extract schema' do
        expect(response).to be_ok
        expect(http_service_entry_span.tags).to_not include(
          match(%r{_dd.appsec.s.req.*}),
          match(%r{_dd.appsec.s.res.*})
        )
      end
    end

    context 'when API security sampler rejects the request' do
      before do
        allow_any_instance_of(Datadog::AppSec::APISecurity::Sampler).to receive(:sample?).and_return(false)

        get('/api/users')
      end

      let(:sampler) { instance_double(Datadog::Tracing::Sampling::Sampler, sample!: true) }

      it 'does not extract schema' do
        expect(response).to be_ok
        expect(http_service_entry_span.tags).to_not include(
          match(%r{_dd.appsec.s.req.*}),
          match(%r{_dd.appsec.s.res.*})
        )
      end
    end
  end

  context 'when API security is disabled' do
    before do
      Datadog.configure do |config|
        config.appsec.api_security.enabled = false
        config.appsec.api_security.sample_delay = 30
      end

      get('/api/users')
    end

    it 'does not extract schema' do
      expect(response).to be_ok
      expect(http_service_entry_span.tags).to_not include(
        match(%r{_dd.appsec.s.req.*}),
        match(%r{_dd.appsec.s.res.*})
      )
    end
  end

  context 'when API security is enabled and running in standalone mode' do
    before do
      Datadog.configure do |config|
        config.apm.tracing.enabled = false
        config.appsec.api_security.enabled = true
        config.appsec.api_security.sample_delay = 30
      end

      get('/api/users')
    end

    let(:sampler) { instance_double(Datadog::Tracing::Sampling::Sampler, sample!: false) }

    it 'extracts request and response schema even if tracer is not sampling' do
      expect(response).to be_ok
      expect(http_service_entry_span.tags).to include(
        match(%r{_dd.appsec.s.req.*}),
        match(%r{_dd.appsec.s.res.*})
      )
    end
  end

  context 'when SQL injection is attempted' do
    before do
      Datadog.configure do |config|
        config.appsec.api_security.enabled = true
        config.appsec.api_security.sample_delay = 30
      end

      get('/api/search', {'name' => "Bob'; OR 1=1"})
    end

    it 'blocks the request and extracts only request schema' do
      expect(response).to be_forbidden
      expect(http_service_entry_span.tags).to include(match(%r{_dd.appsec.s.req.*}))
      expect(http_service_entry_span.tags).not_to include(match(%r{_dd.appsec.s.res.*}))
    end
  end
end
