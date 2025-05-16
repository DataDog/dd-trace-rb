# frozen_string_literal: true

require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/appsec/spec_helper'
require 'rack/test'

require 'datadog/kit/appsec/events'
require 'action_controller/railtie'
require 'active_record'
require 'sqlite3'
require 'devise'

RSpec.describe 'Devise sign up tracking with auto user instrumentation' do
  include Rack::Test::Methods

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
    end

    # app/models
    user_model

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
      config.appsec.instrument :rails
      config.appsec.instrument :devise
      config.appsec.auto_user_instrumentation.mode = 'identification'

      config.remote.enabled = false
    end

    app.initialize!
    app.routes.draw do
      devise_for :users, controllers: { registrations: 'test_registrations' }
    end

    # NOTE: Unfortunately, can't figure out why devise receives 3 times `finalize!`
    #       of the RouteSet patch, hence it's bypassed with below hack.
    #       The order of hacks matters!
    Devise.class_variable_set(:@@warden_configured, nil) # rubocop:disable Style/ClassVars
    Devise.configure_warden!

    # app/controllers
    registrations_controller

    allow(Rails).to receive(:application).and_return(app)
    allow(Datadog::AppSec::Instrumentation).to receive(:gateway).and_return(gateway)

    # NOTE: Don't reach the agent in any way
    allow_any_instance_of(Datadog::Tracing::Transport::HTTP::Client).to receive(:send_request)
    allow_any_instance_of(Datadog::Tracing::Transport::Traces::Transport).to receive(:native_events_supported?)
      .and_return(true)
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

    # Remove Rails caches
    Rails.app_class = nil
    Rails.cache = nil
  end

  let(:registrations_controller) do
    stub_const('TestRegistrationsController', Class.new(Devise::RegistrationsController))
  end

  let(:user_model) do
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
  end

  let(:gateway) { Datadog::AppSec::Instrumentation::Gateway.new }
  let(:http_service_entry_span) { spans.find { |s| s.name == 'rack.request' } }
  let(:http_service_entry_trace) { traces.find { |t| t.id == http_service_entry_span.trace_id } }

  let(:response) { last_response }
  let(:app) { Rails.application }

  context 'when user successfully signed up and immediately login' do
    before do
      form_data = {
        user: { username: 'JohnDoe', email: 'john.doe@example.com', password: '123456', password_confirmation: '123456' }
      }

      post('/users', form_data)
    end

    it 'tracks successful sign up event' do
      expect(response).to be_redirect
      expect(response.location).to eq('http://example.org/')

      expect(http_service_entry_trace.sampling_priority).to eq(Datadog::Tracing::Sampling::Ext::Priority::USER_KEEP)

      expect(http_service_entry_span.tags).to include(
        'usr.id' => '1',
        'appsec.events.users.signup.track' => 'true',
        'appsec.events.users.signup.usr.login' => 'john.doe@example.com',
        '_dd.appsec.events.users.signup.auto.mode' => 'identification',
        '_dd.appsec.usr.login' => 'john.doe@example.com',
        '_dd.appsec.usr.id' => '1'
      )

      expect(gateway.pushed?('appsec.events.user_lifecycle')).to be true
    end
  end

  context 'when user successfully signed up and immediately login, but ID is unavailable' do
    before do
      form_data = {
        user: { username: 'JohnDoe', email: 'john.doe@example.com', password: '123456', password_confirmation: '123456' }
      }

      post('/users', form_data)
    end

    let(:registrations_controller) do
      stub_const('TestRegistrationsController', Class.new(Devise::RegistrationsController)).class_eval do
        def build_resource(hash = {})
          self.resource = resource_class.new_with_session(hash, session)
          resource.instance_eval do
            def save
              true
            end

            def persisted?
              true
            end
          end
        end
      end
    end

    it 'tracks successful sign up event' do
      expect(response).to be_redirect
      expect(response.location).to eq('http://example.org/')

      expect(http_service_entry_trace.sampling_priority).to eq(Datadog::Tracing::Sampling::Ext::Priority::USER_KEEP)

      expect(http_service_entry_span.tags).not_to have_key('usr.id')
      expect(http_service_entry_span.tags).not_to have_key('_dd.appsec.usr.id')
      expect(http_service_entry_span.tags).not_to have_key('appsec.events.users.signup.usr.id')

      expect(http_service_entry_span.tags).to include(
        'appsec.events.users.signup.track' => 'true',
        'appsec.events.users.signup.usr.login' => 'john.doe@example.com',
        '_dd.appsec.events.users.signup.auto.mode' => 'identification',
        '_dd.appsec.usr.login' => 'john.doe@example.com'
      )

      expect(gateway.pushed?('appsec.events.user_lifecycle')).to be true
    end
  end

  context 'when user successfully signed up and must confirm email before loggin in' do
    before do
      form_data = {
        user: { username: 'JohnDoe', email: 'john.doe@example.com', password: '123456', password_confirmation: '123456' }
      }

      post('/users', form_data)
    end

    let(:registrations_controller) do
      stub_const('TestRegistrationsController', Class.new(Devise::RegistrationsController)).class_eval do
        def build_resource(hash = {})
          self.resource = resource_class.new_with_session(hash, session)
          resource.skip_confirmation_notification!
        end
      end
    end

    let(:user_model) do
      stub_const('User', Class.new(ActiveRecord::Base)).tap do |klass|
        klass.establish_connection({ adapter: 'sqlite3', database: ':memory:' })
        klass.connection.create_table 'users', force: :cascade do |t|
          t.string :username, null: false
          t.string :email, default: '', null: false
          t.string :encrypted_password, default: '', null: false
          t.string :confirmation_token
          t.string :unconfirmed_email
          t.datetime :confirmed_at
          t.datetime :confirmation_sent_at
        end

        klass.class_eval do
          devise :database_authenticatable, :confirmable, :registerable, :validatable
        end

        # prevent internal sql requests from showing up
        klass.count
      end
    end

    it 'tracks successful sign up event' do
      expect(response).to be_redirect
      expect(response.location).to eq('http://example.org/')

      expect(http_service_entry_trace.sampling_priority).to eq(Datadog::Tracing::Sampling::Ext::Priority::USER_KEEP)

      expect(http_service_entry_span.tags).to include(
        'appsec.events.users.signup.usr.id' => '1',
        'appsec.events.users.signup.track' => 'true',
        'appsec.events.users.signup.usr.login' => 'john.doe@example.com',
        '_dd.appsec.events.users.signup.auto.mode' => 'identification',
        '_dd.appsec.usr.login' => 'john.doe@example.com',
        '_dd.appsec.usr.id' => '1'
      )

      expect(gateway.pushed?('appsec.events.user_lifecycle')).to be true
    end
  end

  context 'when user successfully signed up and customer uses SDK to set user' do
    before do
      form_data = {
        user: { username: 'JohnDoe', email: 'john.doe@example.com', password: '123456', password_confirmation: '123456' }
      }

      post('/users', form_data)
    end

    let(:registrations_controller) do
      stub_const('TestRegistrationsController', Class.new(Devise::RegistrationsController)).class_eval do
        def create
          Datadog::Kit::AppSec::Events.track_signup(
            Datadog::Tracing.active_trace,
            Datadog::Tracing.active_span,
            user: { id: '42' },
            'usr.login': 'hello@gmail.com'
          )

          super
        end
      end
    end

    let(:user_model) do
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
    end

    it 'tracks successfull sign up event with SDK overrides' do
      expect(response).to be_redirect
      expect(response.location).to eq('http://example.org/')

      expect(http_service_entry_trace.sampling_priority).to eq(Datadog::Tracing::Sampling::Ext::Priority::USER_KEEP)

      expect(http_service_entry_span.tags).to include(
        'usr.id' => '42',
        'appsec.events.users.signup.track' => 'true',
        'appsec.events.users.signup.usr.login' => 'hello@gmail.com',
        '_dd.appsec.events.users.signup.sdk' => 'true',
        '_dd.appsec.events.users.signup.auto.mode' => 'identification',
        '_dd.appsec.usr.login' => 'john.doe@example.com',
        '_dd.appsec.usr.id' => '1'
      )

      expect(gateway.pushed?('appsec.events.user_lifecycle')).to be true
    end
  end
end
