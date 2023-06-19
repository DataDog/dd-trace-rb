require 'rails/all'
require 'ddtrace'

if ENV['USE_SIDEKIQ']
  require 'sidekiq/testing'
  require 'datadog/tracing/contrib/sidekiq/server_tracer'
end

require 'lograge' if ENV['USE_LOGRAGE'] == true
require 'rails_semantic_logger' if ENV['USE_SEMANTIC_LOGGER'] == true

RSpec.shared_context 'Rails base application' do
  if Rails.version >= '6.0'
    require 'datadog/tracing/contrib/rails/support/rails6'
    include_context 'Rails 6 base application'
  elsif Rails.version >= '5.0'
    require 'datadog/tracing/contrib/rails/support/rails5'
    include_context 'Rails 5 base application'
  elsif Rails.version >= '4.0'
    require 'datadog/tracing/contrib/rails/support/rails4'
    include_context 'Rails 4 base application'
  elsif Rails.version >= '3.2'
    require 'datadog/tracing/contrib/rails/support/rails3'
    include_context 'Rails 3 base application'
  else
    logger.error 'A Rails app for this version is not found!'
  end

  # for log_injection testing
  let(:log_output) do
    StringIO.new
  end
  let(:logger) do
    #
    # Use `ActiveSupport::Logger` that contains `ActiveSupport::Logger::SimpleFormatter` to
    # exclude unnecessary metadata. It is almost equivalent to
    #
    # Logger.new(log_output).tap do |l|
    #   l.formatter = ActiveSupport::Logger::SimpleFormatter.new
    # end
    #
    ActiveSupport::Logger.new(log_output)
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
        config.log_tags = ENV['LOG_TAGS'] || {}
        config.rails_semantic_logger.add_file_appender = false
        config.semantic_logger.add_appender(logger: logger)
      end

      middleware.each { |m| config.middleware.use m }
    end
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

        if Rails.version < '4.0'
          this.send(:render, wrapper.status_code, 'Test error response body')
        else
          this.send(:render, wrapper.status_code, 'Test error response body', 'text/plain')
        end
      end
    end
  end
end
