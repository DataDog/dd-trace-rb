require 'spec/datadog/tracing/contrib/rails/support/deprecation'

require 'rails/all'
require 'ddtrace'

if ENV['USE_SIDEKIQ']
  require 'sidekiq/testing'
  require 'datadog/tracing/contrib/sidekiq/server_tracer'
end

require 'lograge' if ENV['USE_LOGRAGE'] == true
require 'rails_semantic_logger' if ENV['USE_SEMANTIC_LOGGER'] == true

RSpec.shared_context 'Rails test application' do
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
end
