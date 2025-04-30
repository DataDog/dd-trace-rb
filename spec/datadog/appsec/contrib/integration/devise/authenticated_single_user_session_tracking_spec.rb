# frozen_string_literal: true

require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/appsec/spec_helper'
require 'rack/test'

require 'action_controller/railtie'
require 'active_record'
require 'sqlite3'
require 'devise'

RSpec.describe 'Devise auto login and signup events session tracking' do
  include Rack::Test::Methods
  include Warden::Test::Helpers

  before do
    # NOTE: By doing this we are emulating the initial load of the devise rails
    #       engine for every test case. It will install the required middleware.
    #       WARNING: This is a hack!
    Devise.send(:remove_const, :Engine)
    load File.join(Gem.loaded_specs['devise'].full_gem_path, 'lib/devise/rails.rb')

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
      klass.establish_connection({ adapter: 'sqlite3', database: ':memory:' })
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
      before_action :configure_permitted_parameters, if: :devise_controller?

      def configure_permitted_parameters
        devise_parameter_sanitizer.permit(:sign_up) do |user|
          user.permit(:username, :email, :password, :password_confirmation)
        end
      end
    end

    # NOTE: Unfortunately, can't figure out why devise receives 3 times `finalize!`
    #       of the RouteSet patch, hence it's bypassed with below hack.
    #       The order of hacks matters!
    allow(Devise).to receive(:regenerate_helpers!)

    # Customer middleware
    customer_middleware

    # Rails app
    # NOTE: https://github.com/heartcombo/devise/blob/fec67f98f26fcd9a79072e4581b1bd40d0c7fa1d/guides/bug_report_templates/integration_test.rb#L43-L57
    app = Class.new(Rails::Application) do
      config.root = __dir__
      config.secret_key_base = 'test-secret-key-base'
      config.action_dispatch.show_exceptions = :rescuable
      config.hosts.clear
      config.eager_load = false
      config.consider_all_requests_local = true
      # NOTE: For debugging replace with $stdout
      config.logger = Rails.logger = Logger.new(StringIO.new)

      config.middleware.insert_before(Warden::Manager, CustomerMiddleware)

      config.file_watcher = Class.new(ActiveSupport::FileUpdateChecker) do
        def initialize(files, dirs = {}, &block)
          dirs = dirs.delete('') if dirs.include?('')

          super(files, dirs, &block)
        end
      end
    end

    stub_const('RailsTest::Application', app)

    Datadog.configure do |config|
      config.tracing.enabled = true
      config.tracing.instrument :rails
      config.tracing.instrument :http

      config.appsec.enabled = true
      config.appsec.ruleset = custom_rules
      config.appsec.instrument :rails
      config.appsec.instrument :devise
      config.appsec.auto_user_instrumentation.mode = 'identification'

      config.remote.enabled = false
    end

    app.initialize!
    app.routes.draw do
      devise_for :users, controllers: { registrations: 'test_registrations' }

      get '/public' => 'public#index'
    end

    # NOTE: Unfortunately, can't figure out why devise receives 3 times `finalize!`
    #       of the RouteSet patch, hence it's bypassed with below hack.
    #       The order of hacks matters!
    Devise.class_variable_set(:@@warden_configured, nil) # rubocop:disable Style/ClassVars
    Devise.configure_warden!

    # app/controllers
    stub_const('PublicController', Class.new(ActionController::Base)).class_eval do
      def index
        respond_to do |format|
          format.html { render plain: 'This is public page' }
        end
      end
    end

    allow(Rails).to receive(:application).and_return(app)
    allow(Datadog::AppSec::Instrumentation).to receive(:gateway).and_return(gateway)

    # NOTE: Don't reach the agent in any way
    allow_any_instance_of(Datadog::Tracing::Transport::HTTP::Client).to receive(:send_request)
    allow_any_instance_of(Datadog::Tracing::Transport::Traces::Transport).to receive(:native_events_supported?)
      .and_return(true)

    Datadog::AppSec::Monitor::Gateway::Watcher.watch
  end

  after do
    clear_traces!

    Datadog.configuration.reset!
    Datadog.registry[:rack].reset_configuration!

    ActiveSupport::Dependencies.clear if Rails.application
    ActiveSupport::Dependencies.autoload_paths = []
    ActiveSupport::Dependencies.autoload_once_paths = []
    ActiveSupport::Dependencies._eager_load_paths = Set.new
    ActiveSupport::Dependencies._autoloaded_tracked_classes = Set.new

    # rubocop:disable Style/ClassVars
    Rails::Railtie::Configuration.class_variable_set(:@@eager_load_namespaces, nil)
    Rails::Railtie::Configuration.class_variable_set(:@@watchable_files, nil)
    Rails::Railtie::Configuration.class_variable_set(:@@watchable_dirs, nil)
    Rails::Railtie::Configuration.class_variable_set(:@@app_generators, nil)
    Rails::Railtie::Configuration.class_variable_set(:@@to_prepare_blocks, nil)
    Rails::Railtie::Configuration.class_variable_set(:@@app_middleware, nil)
    Devise.class_variable_set(:@@mappings, {})
    Devise.class_variable_set(:@@warden_configured, nil)
    # rubocop:enable Style/ClassVars

    # Remnove Rails caches
    Rails.app_class = nil
    Rails.cache = nil
  end

  let(:custom_rules) do
    {
      'version' => '2.1',
      'metadata' => { 'rules_version' => '1.2.6' },
      'rules' => [
        {
          'id' => 'arachni_rule',
          'name' => 'Arachni',
          'tags' => { 'type' => 'security_scanner', 'category' => 'attack_attempt' },
          'conditions' => [
            {
              'parameters' => {
                'inputs' => [
                  {
                    'address' => 'server.request.headers.no_cookies',
                    'key_path' => ['user-agent']
                  }
                ],
                'regex' => '^Arachni\\/v'
              },
              'operator' => 'match_regex'
            }
          ],
          'on_match' => ['block']
        }
      ],
      'scanners' => [],
      'processors' => [
        {
          'id' => 'session-fingerprint',
          'generator' => 'session_fingerprint',
          'conditions' => [],
          'parameters' => {
            'mappings' => [
              {
                'cookies' => [{ 'address' => 'server.request.cookies' }],
                'session_id' => [{ 'address' => 'usr.session_id' }],
                'user_id' => [{ 'address' => 'usr.id' }],
                'output' => '_dd.appsec.fp.session'
              }
            ]
          },
          'evaluate' => true,
          'output' => true
        }
      ]
    }
  end

  let(:customer_middleware) do
    stub_const('CustomerMiddleware', Class.new).class_eval do
      def initialize(app)
        @app = app
      end

      def call(env)
        @app.call(env)
      end
    end
  end

  let(:http_service_entry_span) { spans.find { |s| s.name == 'rack.request' } }
  let(:http_service_entry_trace) { traces.find { |t| t.id == http_service_entry_span.trace_id } }

  let(:gateway) { Datadog::AppSec::Instrumentation::Gateway.new }
  let(:response) { last_response }
  let(:app) { Rails.application }

  context 'when user is not authenticated' do
    it 'allows unauthenticated user to visit public page and does not track it' do
      get('/public')

      expect(response).to be_ok
      expect(response.body).to eq('This is public page')

      expect(http_service_entry_span.tags).not_to have_key('usr.id')
      expect(http_service_entry_span.tags).not_to have_key('usr.session_id')
      expect(http_service_entry_span.tags).not_to have_key('_dd.appsec.fp.session')
    end
  end

  context 'when user is authenticated' do
    before do
      user = User.create!(username: 'JohnDoe', email: 'john.doe@example.com', password: '123456')
      login_as(user)
    end

    it 'allows authenticated user to visit public page and tracks it' do
      get('/public')

      expect(response).to be_ok
      expect(response.body).to eq('This is public page')

      expect(http_service_entry_span.tags).not_to have_key('usr.session_id')
      expect(http_service_entry_span.tags).to include(
        'usr.id' => '1',
        '_dd.appsec.fp.session' => String
      )
    end
  end

  context 'when user is authenticated and customer already uses SDK to set user' do
    before do
      allow_any_instance_of(Datadog::AppSec::Context).to receive(:run_waf).and_call_original

      user = User.create!(username: 'JohnDoe', email: 'john.doe@example.com', password: '123456')
      login_as(user)
    end

    context 'when only user id was set' do
      let(:customer_middleware) do
        stub_const('CustomerMiddleware', Class.new).class_eval do
          def initialize(app)
            @app = app
          end

          def call(env)
            span = Datadog::Tracing.active_span
            trace = Datadog::Tracing.active_trace

            Datadog::Kit::Identity.set_user(trace, span, id: '42')

            @app.call(env)
          end
        end
      end

      it 'tracks it with SDK values and session id from auto-instrumentation' do
        expect_any_instance_of(Datadog::AppSec::Context).to receive(:run_waf)
          .with(hash_including('usr.session_id' => String), anything, anything).once
          .and_call_original

        get('/public')

        expect(response).to be_ok
        expect(response.body).to eq('This is public page')

        expect(http_service_entry_span.tags).not_to have_key('usr.session_id')
        expect(http_service_entry_span.tags).to include(
          'usr.id' => '42',
          '_dd.appsec.fp.session' => String
        )
      end
    end

    context 'when user id and session id were set' do
      let(:customer_middleware) do
        stub_const('CustomerMiddleware', Class.new).class_eval do
          def initialize(app)
            @app = app
          end

          def call(env)
            span = Datadog::Tracing.active_span
            trace = Datadog::Tracing.active_trace

            Datadog::Kit::Identity.set_user(trace, span, id: '42', session_id: '1234567890')

            @app.call(env)
          end
        end
      end

      it 'tracks it with SDK values and customer session id' do
        expect_any_instance_of(Datadog::AppSec::Context).to receive(:run_waf)
          .with(hash_including('usr.session_id' => '1234567890'), anything, anything).once
          .and_call_original

        get('/public')

        expect(response).to be_ok
        expect(response.body).to eq('This is public page')

        expect(http_service_entry_span.tags).to include(
          'usr.id' => '42',
          'usr.session_id' => '1234567890',
          '_dd.appsec.fp.session' => String
        )
      end
    end
  end
end
