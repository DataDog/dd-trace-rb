require 'rails/all'

require 'ddtrace' if ENV['TEST_AUTO_INSTRUMENT'] == true

if ENV['USE_SIDEKIQ']
  require 'sidekiq/testing'
  require 'datadog/tracing/contrib/sidekiq/server_tracer'
end

require 'datadog/tracing/contrib/rails/support/controllers'
require 'datadog/tracing/contrib/rails/support/middleware'
require 'datadog/tracing/contrib/rails/support/models'

RSpec.shared_context 'Rails 5 base application' do
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
      redis_cache =
        if Gem.loaded_specs['redis-activesupport']
          [:redis_store, { url: ENV['REDIS_URL'] }]
        else
          [:redis_cache_store, { url: ENV['REDIS_URL'] }]
        end
      file_cache = [:file_store, '/tmp/ddtrace-rb/cache/']

      config.secret_key_base = 'f624861242e4ccf20eacb6bb48a886da'
      config.cache_store = ENV['REDIS_URL'] ? redis_cache : file_cache
      config.eager_load = false
      config.consider_all_requests_local = true

      instance_eval(&during_init)

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

    before_test_init = before_test_initialize_block
    after_test_init = after_test_initialize_block

    klass.send(:define_method, :test_initialize!) do
      # we want to disable explicit instrumentation
      # when testing auto patching
      if ENV['TEST_AUTO_INSTRUMENT'] == 'true'
        require 'ddtrace/auto_instrument'
      else
        # Enables the auto-instrumentation for the testing application
        Datadog.configure do |c|
          c.tracing.instrument :rails
          c.tracing.instrument :redis if Gem.loaded_specs['redis'] && defined?(::Redis)
        end
      end

      Rails.application.config.active_job.queue_adapter = if ENV['USE_SIDEKIQ']
                                                            :sidekiq
                                                          else
                                                            :inline
                                                          end

      before_test_init.call
      initialize!
      after_test_init.call
    end
    klass
  end

  let(:rails_test_application) do
    stub_const('Rails5::Application', Class.new(rails_base_application))
  end

  let(:app) do
    initialize_app!
    rails_test_application.instance
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
      application_record.connection

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

  # for log_injection testing
  let(:log_output) do
    StringIO.new
  end

  let(:logger) do
    # Use `ActiveSupport::Logger::SimpleFormatter` to exclude unnecessary metadata.
    #
    # This must not be replaced by `ActiveSupport::Logger` instance with `ActiveSupport::Logger.new(log_output)`,
    # because RailsSemanticLogger monkey patch
    #
    # see: https://github.com/reidmorrison/rails_semantic_logger/tree/master/lib/rails_semantic_logger/extensions/active_support
    Logger.new(log_output).tap do |l|
      l.formatter = ActiveSupport::Logger::SimpleFormatter.new
    end
  end

  let(:initialize_block) do
    middleware = rails_middleware
    logger = self.logger

    proc do
      #
      # It is important to distinguish between `nil` and an empty array.
      #
      # If `nil` (which is the default), `Rails::Rack::Logger` would initialize with an new array.
      # https://github.com/rails/rails/blob/e88857bbb9d4e1dd64555c34541301870de4a45b/railties/lib/rails/application/default_middleware_stack.rb#L51
      #
      # Datadog integration need to provide an array during `before_initialize` hook
      #
      config.log_tags = ENV['LOG_TAGS'] if ENV['LOG_TAGS']

      config.logger = if ENV['USE_TAGGED_LOGGING'] == true
                        ActiveSupport::TaggedLogging.new(logger)
                      else
                        logger
                      end

      # Not to use ANSI color codes when logging information
      config.colorize_logging = false

      if config.respond_to?(:lograge)
        # `keep_original_rails_log` is important to prevent monkey patching from `lograge`
        #  which leads to flaky spec in the same test process
        config.lograge.keep_original_rails_log = true
        config.lograge.logger = config.logger

        if ENV['USE_LOGRAGE'] == true
          config.lograge.enabled = true
          config.lograge.custom_options = ENV['LOGRAGE_CUSTOM_OPTIONS'] if ENV['LOGRAGE_CUSTOM_OPTIONS']
        else
          # ensure no test leakage from other tests
          config.lograge.enabled = false
        end
      end

      # Semantic Logger settings should be exclusive to `ActiveSupport::TaggedLogging` and `Lograge`
      if ENV['USE_SEMANTIC_LOGGER'] == true
        config.rails_semantic_logger.add_file_appender = false
        config.semantic_logger.add_appender(logger: logger)
      end

      middleware.each { |m| config.middleware.use m }
    end
  end

  before do
    reset_rails_configuration!
    reset_lograge_configuration! if defined?(::Lograge)
    raise_on_rails_deprecation!
  end

  after do
    reset_rails_configuration!
    reset_lograge_configuration! if defined?(::Lograge)
    reset_lograge_subscription! if defined?(::Lograge)
    reset_rails_semantic_logger_subscription! if defined?(::RailsSemanticLogger)

    # Reset references stored in the Rails class
    Rails.application = nil
    Rails.logger = nil

    Rails.app_class = nil
    Rails.cache = nil

    without_warnings { Datadog.configuration.reset! }
    Datadog.configuration.tracing[:rails].reset_options!
    Datadog.configuration.tracing[:rack].reset_options!
    Datadog.configuration.tracing[:redis].reset_options!
  end

  def initialize_app!
    # Reinitializing Rails applications generates a lot of warnings.
    without_warnings do
      # Initialize the application and stub Rails with the test app
      rails_test_application.test_initialize!
    end

    # Clear out any spans generated during initialization
    clear_traces!
    # Clear out log entries generated during initialization
    log_output.reopen
  end

  def reset_lograge_configuration!
    # Reset the global
    ::Lograge.logger = nil
    ::Lograge.application = nil
    ::Lograge.custom_options = nil
    ::Lograge.ignore_tests = nil
    ::Lograge.before_format = nil
    ::Lograge.log_level = nil
    ::Lograge.formatter = nil
  end

  def reset_lograge_subscription!
    # Unsubscribe log subscription to prevent flaky specs due to multiple subscription
    # after several test cases.
    #
    # This should be equivalent to:
    #
    #   ::Lograge::LogSubscribers::ActionController.detach_from :action_controller
    #   ::Lograge::ActionView::LogSubscriber.detach_from :action_view
    #
    # Currently, no good way to unsubscribe ActionCable, since it is monkey patched by lograge
    #
    # To Debug:
    #
    # puts "Before: ===================="
    # puts ActiveSupport::LogSubscriber.log_subscribers
    # puts "Before: ===================="
    unsubscribe(ActiveSupport::LogSubscriber.log_subscribers.select { |s| ::Lograge::LogSubscribers::Base === s })
    # To Debug:
    #
    # puts "After: ===================="
    # puts ActiveSupport::LogSubscriber.log_subscribers
    # puts "After: ===================="
  end

  def reset_rails_semantic_logger_subscription!
    # Unsubscribe log subscription to prevent flaky specs due to multiple subscription
    # after several test cases.
    # This should be equivalent to:
    #
    #   RailsSemanticLogger::ActionController::LogSubscriber.detach_from :action_controller
    #   RailsSemanticLogger::ActionView::LogSubscriber.detach_from :action_view
    #   ...
    #
    # To Debug:
    #
    # puts "Before: ===================="
    # puts ActiveSupport::LogSubscriber.log_subscribers
    # puts "Before: ===================="
    unsubscribe(
      ActiveSupport::LogSubscriber.log_subscribers.select do |s|
        s.class.name.start_with? 'RailsSemanticLogger::'
      end
    )
    # To Debug:
    #
    # puts "After: ===================="
    # puts ActiveSupport::LogSubscriber.log_subscribers
    # puts "After: ===================="
  end

  # Backporting `ActiveSupport::Subscriber#detach_from` implementation for older Rails
  def unsubscribe(subscribers)
    subscribers.each do |subscriber|
      patterns = if subscriber.patterns.respond_to?(:keys)
                   subscriber.patterns.keys
                 else
                   subscriber.patterns
                 end
      patterns.each do |pattern|
        ActiveSupport::Notifications.notifier.listeners_for(pattern).each do |listener|
          ActiveSupport::Notifications.unsubscribe listener if listener.instance_variable_get('@delegate') == subscriber
        end
      end
      ActiveSupport::LogSubscriber.log_subscribers.delete(subscriber)
    end
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
  end

  def append_controllers!
    controllers
  end

  # Rails 5 leaves a bunch of global class configuration on Rails::Railtie::Configuration in class variables
  # We need to reset these so they don't carry over between example runs
  def reset_rails_configuration!
    # Reset autoloaded constants
    ActiveSupport::Dependencies.clear if Rails.application

    # TODO: Remove this side-effect on missing log entries
    Lograge.remove_existing_log_subscriptions if defined?(::Lograge)

    Rails::Railtie::Configuration.class_variable_set(:@@eager_load_namespaces, nil)
    Rails::Railtie::Configuration.class_variable_set(:@@watchable_files, nil)
    Rails::Railtie::Configuration.class_variable_set(:@@watchable_dirs, nil)
    if Rails::Railtie::Configuration.class_variable_defined?(:@@app_middleware)
      Rails::Railtie::Configuration.class_variable_set(:@@app_middleware, Rails::Configuration::MiddlewareStackProxy.new)
    end
    Rails::Railtie::Configuration.class_variable_set(:@@app_generators, nil)
    Rails::Railtie::Configuration.class_variable_set(:@@to_prepare_blocks, nil)
  end
end
