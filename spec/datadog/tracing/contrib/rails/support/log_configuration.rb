require_relative 'backport'

RSpec.shared_context 'Rails log configuration' do
  around do |example|
    reset_lograge_configuration! if defined?(::Lograge)
    example.run
    reset_lograge_configuration! if defined?(::Lograge)
  end

  # Unsubscribe log subscription to prevent flaky specs due to multiple subscription
  # after several test cases.
  after do
    # To Debug:
    #
    # puts "Before: ===================="
    # puts ActiveSupport::LogSubscriber.log_subscribers
    # puts "Before: ===================="
    LogrageSubscription.reset! if defined?(::Lograge)
    RailsSemanticLoggerSubscription.reset! if defined?(::RailsSemanticLogger)
    # To Debug:
    #
    # puts "After: ===================="
    # puts ActiveSupport::LogSubscriber.log_subscribers
    # puts "After: ===================="
  end

  let(:lograge_options) do
    {}
  end

  let(:log_tags) do
    nil
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
      l.formatter = if defined?(::ActiveSupport::Logger::SimpleFormatter)
                      ::ActiveSupport::Logger::SimpleFormatter.new
                    else
                      l.formatter = proc do |_, _, _, msg|
                        "#{String === msg ? msg : msg.inspect}\n"
                      end
                    end
    end
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
end

module LogrageSubscription
  module_function

  def reset!
    # Currently, no good way to unsubscribe ActionCable, since it is monkey patched by lograge
    #
    # `ActiveSupport::Subscriber.detach_from` is available from 6+
    if ::ActiveSupport::Subscriber.respond_to? :detach_from
      ::Lograge::LogSubscribers::ActionController.detach_from :action_controller
    else
      ::Datadog::Tracing::Contrib::Rails::Test::Backport.unsubscribe(
        ::ActiveSupport::LogSubscriber.log_subscribers.select { |s| ::Lograge::LogSubscribers::Base === s }
      )
    end
  end
end

# Utility functions for rails_semantic_logger subscription
module RailsSemanticLoggerSubscription
  module_function

  def reset!
    # `ActiveSupport::Subscriber.detach_from` is available from 6+
    if ::ActiveSupport::Subscriber.respond_to? :detach_from
      ::RailsSemanticLogger::ActionController::LogSubscriber.detach_from :action_controller
      ::RailsSemanticLogger::ActionView::LogSubscriber.detach_from :action_view
    else
      ::Datadog::Tracing::Contrib::Rails::Test::Backport.unsubscribe(
        ::ActiveSupport::LogSubscriber.log_subscribers.select do |s|
          s.class.name.start_with? 'RailsSemanticLogger::'
        end
      )
    end
  end
end

module Datadog
  module Tracing
    module Contrib
      module Rails
        module Test
          # Configure logging in test
          class LogConfiguration
            def initialize(example_group)
              @example_group = example_group
            end

            def setup(config)
              config.log_tags = example_group.log_tags if example_group.log_tags

              config.logger = example_group.logger

              # Not to use ANSI color codes when logging information
              config.colorize_logging = false

              if config.respond_to?(:lograge)
                LogrageConfiguration.setup!(config, OpenStruct.new(example_group.lograge_options))
              end

              # Semantic Logger settings should be exclusive to `ActiveSupport::TaggedLogging` and `Lograge`
              if config.respond_to?(:rails_semantic_logger)
                config.rails_semantic_logger.add_file_appender = false
                config.semantic_logger.add_appender(logger: config.logger)
              end
            end

            private

            attr_reader :example_group

            # Configure lograge in test
            module LogrageConfiguration
              module_function

              def setup!(config, lograge)
                # `keep_original_rails_log` is important to prevent monkey patching from `lograge`
                #  which leads to flaky spec in the same test process
                config.lograge.keep_original_rails_log = true
                config.lograge.logger = config.logger

                config.lograge.enabled = !!lograge.enabled?
                config.lograge.custom_options = lograge.custom_options
              end
            end
          end
        end
      end
    end
  end
end
