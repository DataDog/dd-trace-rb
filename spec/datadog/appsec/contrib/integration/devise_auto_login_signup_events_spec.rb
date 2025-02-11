# frozen_string_literal: true

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
      config.parent_controller = 'TestBaseController'
      config.paranoid = true
      config.stretches = 1
    end

    # app/models
    stub_const('User', Class.new(ActiveRecord::Base)).tap do |klass|
      klass.establish_connection({ adapter: 'sqlite3', database: ':memory:' })
      klass.connection.create_table 'users', force: :cascade do |t|
        t.string :name, null: false
        t.string :email, default: '', null: false
        t.string :encrypted_password, default: '', null: false
        t.datetime :remember_created_at
        t.datetime :created_at, null: false
        t.datetime :updated_at, null: false
      end

      klass.class_eval do
        devise :database_authenticatable, :rememberable
      end

      # prevent internal sql requests from showing up
      klass.count
    end

    stub_const('TestBaseController', Class.new(ActionController::Base))

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
      # config.enable_reloading = false
      # config.action_controller.perform_caching = false
      # config.cache_store = :null_store
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

    Datadog.configure do |c|
      c.tracing.enabled = true
      c.tracing.instrument :rack

      c.appsec.enabled = true
      c.appsec.instrument :devise

      c.remote.enabled = false
    end

    allow_any_instance_of(Datadog::Tracing::Transport::HTTP::Client).to receive(:send_request)
  end

  after do
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
  end

  let(:response) { last_response }
  let(:app) { Rails.application }

  let(:http_service_entry_span) do
    Datadog::Tracing::Transport::TraceFormatter.format!(trace)
    spans.find { |s| s.name == 'rack.request' }
  end

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

  context 'when user loggin in' do
    before { User.create!(name: 'John Doe', email: 'john.doe@example.com', password: '123456') }

    it 'tracks successful login event' do
      post('/users/sign_in', { user: { email: 'john.doe@example.com', password: '123456' } })

      expect(response).to be_redirect
      expect(response.location).to eq('http://example.org/')

      # TODO: Add tests for correct span tags
    end
  end
end
