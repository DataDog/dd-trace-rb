require 'rails/all'
require 'ddtrace'

if ENV['USE_SIDEKIQ']
  require 'sidekiq/testing'
  require 'ddtrace/contrib/sidekiq/server_tracer'
end

require 'ddtrace/contrib/rails/support/controllers'
require 'ddtrace/contrib/rails/support/middleware'
require 'ddtrace/contrib/rails/support/models'

RSpec.shared_context 'Rails 6 base application' do
  include_context 'Rails controllers'
  include_context 'Rails middleware'
  include_context 'Rails models'

  let(:rails_base_application) do
    klass = Class.new(Rails::Application) do
      def config.database_configuration
        parsed = super
        raise parsed.to_yaml # Replace this line to add custom connections to the hash from database.yml
      end
    end
    during_init = initialize_block

    klass.send(:define_method, :initialize) do |*args|
      super(*args)
      redis_cache = [:redis_cache_store, { url: ENV['REDIS_URL'] }]
      file_cache = [:file_store, '/tmp/ddtrace-rb/cache/']

      config.load_defaults '6.0'
      config.secret_key_base = 'f624861242e4ccf20eacb6bb48a886da'
      config.cache_store = ENV['REDIS_URL'] ? redis_cache : file_cache
      config.eager_load = false
      config.consider_all_requests_local = true

      # Avoid eager-loading Rails sub-component, ActionDispatch, before initialization
      config.middleware.delete ActionDispatch::DebugExceptions if defined?(ActionDispatch::DebugExceptions)

      instance_eval(&during_init)

      if ENV['USE_SIDEKIQ']
        config.active_job.queue_adapter = :sidekiq
        # add Sidekiq middleware
        Sidekiq::Testing.server_middleware do |chain|
          chain.add(
            Datadog::Contrib::Sidekiq::ServerTracer
          )
        end
      end
    end

    before_test_init = before_test_initialize_block
    after_test_init = after_test_initialize_block

    klass.send(:define_method, :test_initialize!) do
      # Enables the auto-instrumentation for the testing application
      Datadog.configure do |c|
        c.use :rails
        c.use :redis if Gem.loaded_specs['redis'] && defined?(::Redis)
      end

      Rails.application.config.active_job.queue_adapter = :sidekiq

      before_test_init.call
      initialize!
      after_test_init.call
    end
    klass
  end

  def append_routes!
    # Make sure to load controllers first
    # otherwise routes won't draw properly.
    test_routes = routes

    rails_test_application.instance.routes.append do
      test_routes.each do |k, v|
        get k => v
      end
    end

    # ActionText requires ApplicationController to be loaded since Rails 6
    example = self
    ActiveSupport.on_load(:action_text_content) do
      example.stub_const('ApplicationController', Class.new(ActionController::Base))
    end
  end

  def append_controllers!
    controllers
  end

  # Rails 5 leaves a bunch of global class configuration on Rails::Railtie::Configuration in class variables
  # We need to reset these so they don't carry over between example runs
  def reset_rails_configuration!
    # Reset autoloaded constants
    ActiveSupport::Dependencies.clear if Rails.application

    reset_class_variable(ActiveRecord::Railtie::Configuration, :@@options)
    # After `deep_dup`, the sentinel `NULL_OPTION` is inadvertently changed. We restore it here.
    ActiveRecord::Railtie.config.action_view.finalize_compiled_template_methods = ActionView::Railtie::NULL_OPTION

    reset_class_variable(ActiveSupport::Dependencies, :@@autoload_paths)
    reset_class_variable(ActiveSupport::Dependencies, :@@autoload_once_paths)
    reset_class_variable(ActiveSupport::Dependencies, :@@_eager_load_paths)

    Rails::Railtie::Configuration.class_variable_set(:@@eager_load_namespaces, nil)
    Rails::Railtie::Configuration.class_variable_set(:@@watchable_files, nil)
    Rails::Railtie::Configuration.class_variable_set(:@@watchable_dirs, nil)
    if Rails::Railtie::Configuration.class_variable_defined?(:@@app_middleware)
      Rails::Railtie::Configuration.class_variable_set(:@@app_middleware, Rails::Configuration::MiddlewareStackProxy.new)
    end
    Rails::Railtie::Configuration.class_variable_set(:@@app_generators, nil)
    Rails::Railtie::Configuration.class_variable_set(:@@to_prepare_blocks, nil)
  end

  # Resets configuration that needs to be restored to its original value
  # between each run of a Rails application.
  def reset_class_variable(clazz, variable)
    value = Datadog::Contrib::Rails::Test::Configuration.fetch(
      "#{clazz}.#{variable}",
      clazz.class_variable_get(variable)
    )

    clazz.class_variable_set(variable, value.deep_dup)
  end
end
