# Loaded by the `bin/rails` script in a real Rails application
require 'rails/command'

# We may not always want to require rails/all, especially when we don't have a database.
# require is already done where Rails test application is used, manually or through rails_helper.

if ENV['USE_SIDEKIQ']
  require 'sidekiq/testing'
  require 'datadog/tracing/contrib/sidekiq/server_tracer'
end

RSpec.shared_context 'Rails 7 test application' do
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
      redis_cache =
        if Gem.loaded_specs['redis-activesupport']
          [:redis_store, { url: ENV['REDIS_URL'] }]
        else
          [:redis_cache_store, { url: ENV['REDIS_URL'] }]
        end
      file_cache = [:file_store, '/tmp/datadog-rb/cache/']

      config.load_defaults '7.0'
      config.secret_key_base = 'f624861242e4ccf20eacb6bb48a886da'
      config.active_record.cache_versioning = false if Gem.loaded_specs['redis-activesupport']
      config.cache_store = ENV['REDIS_URL'] ? redis_cache : file_cache
      config.eager_load = false
      config.consider_all_requests_local = true
      config.hosts.clear # Allow requests for any hostname during tests
      config.active_support.remove_deprecated_time_with_zone_name = false

      instance_eval(&during_init)

      if defined?(ActiveJob)
        config.active_job.queue_adapter = :inline
        if ENV['USE_SIDEKIQ']
          config.active_job.queue_adapter = :sidekiq
          # add Sidekiq middleware
          Sidekiq::Testing.server_middleware do |chain|
            chain.add(
              Datadog::Tracing::Contrib::Sidekiq::ServerTracer
            )
          end
        end
      end
    end

    before_test_init = before_test_initialize_block
    after_test_init = after_test_initialize_block

    klass.send(:define_method, :test_initialize!) do
      # we want to disable explicit instrumentation
      # when testing auto patching
      if ENV['TEST_AUTO_INSTRUMENT'] == 'true'
        require 'datadog/auto_instrument'
      else
        # Enables the auto-instrumentation for the testing application
        Datadog.configure do |c|
          c.tracing.instrument :rails
          c.tracing.instrument :redis if Gem.loaded_specs['redis'] && defined?(::Redis)
        end
      end

      if defined?(ActiveJob)
        Rails.application.config.active_job.queue_adapter = ENV['USE_SIDEKIQ'] ? :sidekiq : :inline
      end

      Rails.application.config.file_watcher = Class.new(ActiveSupport::FileUpdateChecker) do
        # When running in full application mode, Rails tries to monitor
        # the file system for changes. This causes issues when using
        # {ActionView::FixtureResolver} to mock the filesystem for templates
        # as this test resolver wasn't meant to work with a full application.
        #
        # Because {ActionView::FixtureResolver} doesn't have a complete filesystem,
        # it sets its base path to '', which later in the file watcher gets translated to:
        # "Monitor '**/*' for changes", which means monitoring the whole system, causing
        # many "permission denied errors".
        #
        # This method removes the blank path ('') created by {ActionView::FixtureResolver}
        # in order to allow the file watcher to skip monitoring the "filesystem changes"
        # of the in-memory fixtures.
        def initialize(files, dirs = {}, &block)
          dirs = dirs.delete('') if dirs.include?('')

          super(files, dirs, &block)
        end
      end

      before_test_init.call
      initialize!
      after_test_init.call
    end
    Class.new(klass)
  end

  let(:before_test_initialize_block) do
    proc do
      append_routes!
    end
  end

  let(:after_test_initialize_block) do
    proc do
      # Rails autoloader recommends controllers to be loaded
      # after initialization. This will be enforced when `zeitwerk`
      # becomes the only supported autoloader.
      append_controllers!

      # Force connection to initialize, and dump some spans
      application_record.connection unless (defined? no_db) && no_db

      # Skip default Rails exception page rendering.
      # This avoid polluting the trace under test
      # with render and partial_render templates for the
      # error page.
      #
      # We could completely disable the {DebugExceptions} middleware,
      # but that affects Rails' internal error propagation logic.
      # render_for_browser_request(request, wrapper)
      allow_any_instance_of(::ActionDispatch::DebugExceptions).to receive(:render_exception) do |this, env, exception|
        wrapper = ::ActionDispatch::ExceptionWrapper.new(env, exception)

        this.send(:render, wrapper.status_code, 'Test error response body', 'text/plain')
      end
    end
  end

  before do
    reset_rails_configuration!
  end

  after do
    reset_rails_configuration!

    # Push this to base when Rails 3 removed
    # Reset references stored in the Rails class
    Rails.app_class = nil
    Rails.cache = nil
  end

  def append_routes!
    # Make sure to load controllers first
    # otherwise routes won't draw properly.
    test_routes = routes

    rails_test_application.instance.routes.append do
      test_routes.each do |k, v|
        if k.is_a?(Array)
          send(k.first, k.last => v)
        else
          get k => v
        end
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

  # Rails leaves a bunch of global class configuration on Rails::Railtie::Configuration in class variables
  # We need to reset these so they don't carry over between example runs
  def reset_rails_configuration!
    # Reset autoloaded constants
    ActiveSupport::Dependencies.clear if Rails.application

    # TODO: Remove this side-effect on missing log entries
    Lograge.remove_existing_log_subscriptions if defined?(::Lograge)

    if Module.const_defined?(:ActiveRecord)
      reset_class_variable(ActiveRecord::Railtie::Configuration, :@@options)

      # After `deep_dup`, the sentinel `NULL_OPTION` is inadvertently changed. We restore it here.
      if Rails::VERSION::MINOR < 1
        ActiveRecord::Railtie.config.action_view.finalize_compiled_template_methods = ActionView::Railtie::NULL_OPTION
      end
    end

    ActiveSupport::Dependencies.autoload_paths = []
    ActiveSupport::Dependencies.autoload_once_paths = []
    ActiveSupport::Dependencies._eager_load_paths = Set.new
    ActiveSupport::Dependencies._autoloaded_tracked_classes = Set.new

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
    value = Datadog::Tracing::Contrib::Rails::Test::Configuration.fetch(
      "#{clazz}.#{variable}",
      clazz.class_variable_get(variable)
    )

    clazz.class_variable_set(variable, value.deep_dup)
  end
end
