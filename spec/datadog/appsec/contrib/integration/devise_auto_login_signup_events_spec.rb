# frozen_string_literal: true

require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/appsec/spec_helper'
require 'rack/test'

require 'action_controller/railtie'
require 'active_record'
require 'sqlite3'
require 'devise'

RSpec.describe 'Devise auto login and signup events tracking' do
  include Rack::Test::Methods
  include Warden::Test::Helpers

  before do
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
    stub_const('User', Class.new(ActiveRecord::Base)).tap do |klass|
      klass.establish_connection({ adapter: 'sqlite3', database: ':memory:' })
      klass.connection.create_table 'users', force: :cascade do |t|
        t.string :username, null: false
        t.string :email, default: '', null: false
        t.string :encrypted_password, default: '', null: false
        t.datetime :remember_created_at
        t.datetime :created_at, null: false
        t.datetime :updated_at, null: false
      end

      klass.class_eval do
        devise :database_authenticatable, :registerable, :validatable, :rememberable
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

    # Rails app
    # NOTE: https://github.com/heartcombo/devise/blob/fec67f98f26fcd9a79072e4581b1bd40d0c7fa1d/guides/bug_report_templates/integration_test.rb#L43-L57
    app = Class.new(Rails::Application) do
      config.root = __dir__
      config.secret_key_base = 'test-secret-key-base'
      config.action_dispatch.show_exceptions = :rescuable
      config.hosts.clear
      config.eager_load = false
      config.consider_all_requests_local = true
      config.logger = Rails.logger = Logger.new($stdout)

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

      config.remote.enabled = false
    end

    app.initialize!
    app.routes.draw do
      devise_for :users

      get '/public' => 'public#index'
      get '/private' => 'private#index'
    end

    # NOTE: Unfortunately, can't figure out why devise receives 3 times `finalize!`
    #       of the RouteSet patch, hence it's bypassed with below hack.
    #       The order of hacks matters!
    Devise.class_variable_set(:@@warden_configured, nil) # rubocop:disable Style/ClassVars
    Devise.configure_warden!

    # app/controllers
    stub_const('PrivateController', Class.new(ActionController::Base)).class_eval do
      before_action :authenticate_user!

      def index
        respond_to do |format|
          format.html { render plain: 'This is private page' }
        end
      end
    end
    stub_const('PublicController', Class.new(ActionController::Base)).class_eval do
      def index
        respond_to do |format|
          format.html { render plain: 'This is public page' }
        end
      end
    end

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
    if Rails::Railtie::Configuration.class_variable_defined?(:@@app_middleware)
      Rails::Railtie::Configuration.class_variable_set(:@@app_middleware, Rails::Configuration::MiddlewareStackProxy.new)
    end
    Rails::Railtie::Configuration.class_variable_set(:@@app_generators, nil)
    Rails::Railtie::Configuration.class_variable_set(:@@to_prepare_blocks, nil)
    # rubocop:enable Style/ClassVars

    # Remnove Rails caches
    Rails.app_class = nil
    Rails.cache = nil
  end

  let(:http_service_entry_span) { spans.find { |s| s.name == 'rack.request' } }
  let(:http_service_entry_trace) { traces.find { |t| t.id == http_service_entry_span.trace_id } }

  let(:response) { last_response }
  let(:app) { Rails.application }

  context 'when user is not authenticated' do
    it 'allows unauthenticated user to visit public page' do
      get('/public')

      expect(response).to be_ok
      expect(response.body).to eq('This is public page')
    end

    it 'forbids unauthenticated user to visit private page' do
      get('/private')

      expect(response).to be_redirect
      expect(response.location).to match('users/sign_in')
    end
  end

  context 'when user instrumentation mode set to identification' do
    before { Datadog.configuration.appsec.auto_user_instrumentation.mode = 'identification' }

    context 'when user successfully loggin' do
      before do
        User.create!(username: 'JohnDoe', email: 'john.doe@example.com', password: '123456')

        post('/users/sign_in', { user: { email: 'john.doe@example.com', password: '123456' } })
      end

      it 'tracks successfull login event' do
        expect(response).to be_redirect
        expect(response.location).to eq('http://example.org/')

        expect(http_service_entry_trace.sampling_priority).to eq(Datadog::Tracing::Sampling::Ext::Priority::USER_KEEP)

        expect(http_service_entry_span.tags['appsec.events.users.login.success.track']).to eq('true')
        expect(http_service_entry_span.tags['_dd.appsec.events.users.login.success.auto.mode']).to eq('extended')
        expect(http_service_entry_span.tags['usr.id']).to eq('1')

        # NOTE: not implemented yet
        # expect(http_service_entry_span.tags['appsec.events.users.login.success.usr.login']).to eq('john.doe@example.com')
        # expect(http_service_entry_span.tags['_dd.appsec.usr.login']).to eq('john.doe@example.com')
        # expect(http_service_entry_span.tags['_dd.appsec.usr.id']).to eq('1')
      end
    end

    context 'when user unsuccessfully loggin because such user does not exist' do
      before { post('/users/sign_in', { user: { email: 'john.doe@example.com', password: '123456' } }) }

      it 'tracks login failure event' do
        expect(response).to be_unprocessable
        expect(response.body).to match(%r{<form .* action="/users/sign_in" .*>})

        expect(http_service_entry_trace.sampling_priority).to eq(Datadog::Tracing::Sampling::Ext::Priority::USER_KEEP)

        expect(http_service_entry_span.tags['appsec.events.users.login.failure.track']).to eq('true')
        expect(http_service_entry_span.tags['_dd.appsec.events.users.login.failure.auto.mode']).to eq('extended')
        expect(http_service_entry_span.tags['appsec.events.users.login.failure.usr.exists']).to eq('false')

        # NOTE: not implemented yet
        # expect(http_service_entry_span.tags['_dd.appsec.usr.login']).to eq('john.doe@example.com')
        # expect(http_service_entry_span.tags['appsec.events.users.login.failure.usr.login']).to eq('john.doe@example.com')
      end
    end

    # context 'when user unsuccessfully loggin because it is not permitted by custom logic' do
    # NOTE: When possible to have user and user exists, but for some validation
    #       reasons it could not be authorized, we should report it
    #       - `appsec.events.users.login.failure.usr.id`
    #       - `_dd.appsec.usr.id`
    # end

    context 'when user successfully signed up' do
      before do
        form_data = {
          user: { username: 'JohnDoe', email: 'john.doe@example.com', password: '123456', password_confirmation: '123456' }
        }

        post('/users', form_data)
      end

      it 'tracks successfull sign up event' do
        expect(response).to be_redirect
        expect(response.location).to eq('http://example.org/')

        expect(http_service_entry_trace.sampling_priority).to eq(Datadog::Tracing::Sampling::Ext::Priority::USER_KEEP)

        expect(http_service_entry_span.tags['appsec.events.users.signup.track']).to eq('true')
        expect(http_service_entry_span.tags['_dd.appsec.events.users.signup.auto.mode']).to eq('extended')

        # NOTE: not implemented yet
        # expect(http_service_entry_span.tags['appsec.events.users.signup.usr.login']).to eq('john.doe@example.com')
        # expect(http_service_entry_span.tags['_dd.appsec.usr.login']).to eq('john.doe@example.com')
        # expect(http_service_entry_span.tags['appsec.events.users.signup.usr.id']).to eq('1')
        # expect(http_service_entry_span.tags['_dd.appsec.usr.id']).to eq('1')
      end
    end
  end
end
