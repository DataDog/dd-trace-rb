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
    # Use `ActiveSupport::Logger::SimpleFormatter` to exclude unnecessary metadata.
    #
    # This must not be replaced by `ActiveSupport::Logger` instance with `ActiveSupport::Logger.new(log_output)`,
    # because RailsSemanticLogger monkey patch
    #
    # see: https://github.com/reidmorrison/rails_semantic_logger/tree/master/lib/rails_semantic_logger/extensions/active_support
    Logger.new(log_output).tap do |l|
      l.formatter = if defined?(ActiveSupport::Logger::SimpleFormatter)
                      ActiveSupport::Logger::SimpleFormatter.new
                    else
                      proc do |_, _, _, msg|
                        "#{String === msg ? msg : msg.inspect}\n"
                      end
                    end
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
end
