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
  let(:log_output) { StringIO.new }
  let(:logger) do
    Logger.new(log_output)
  end

  let(:initialize_block) do
    middleware = rails_middleware
    logger = self.logger

    proc do
      if ENV['USE_TAGGED_LOGGING'] == true
        config.log_tags = ENV['LOG_TAGS'] || []
        Rails.logger = ActiveSupport::TaggedLogging.new(logger)
      end

      if ENV['USE_SEMANTIC_LOGGER'] == true
        config.log_tags = ENV['LOG_TAGS'] || {}
        config.rails_semantic_logger.add_file_appender = false
        config.semantic_logger.add_appender(logger: logger)
      end

      if ENV['USE_LOGRAGE'] == true
        config.logger = logger

        config.lograge.custom_options = ENV['LOGRAGE_CUSTOM_OPTIONS'] unless ENV['LOGRAGE_CUSTOM_OPTIONS'].nil?

        if ENV['LOGRAGE_DISABLED'].nil?
          config.lograge.enabled = true
          config.lograge.base_controller_class = 'LogrageTestController'
          config.lograge.logger = logger
        else
          config.lograge.enabled = false
        end
      # ensure no test leakage from other tests
      elsif config.respond_to?(:lograge)
        config.lograge.enabled = false
        config.lograge.keep_original_rails_log = true
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
