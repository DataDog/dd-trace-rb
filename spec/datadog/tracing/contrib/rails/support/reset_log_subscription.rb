require_relative 'backport'

RSpec.shared_context 'Reset log subscription' do
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
end

# Utility functions for lograge subscription
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
