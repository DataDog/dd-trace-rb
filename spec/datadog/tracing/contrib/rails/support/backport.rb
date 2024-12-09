module Datadog
  module Tracing
    module Contrib
      module Rails
        module Test
          # Backport utilities for older Rails for easier testing
          module Backport
            module_function

            # `ActiveSupport::Subscriber.detach_from` implementation for Rails < 6
            def unsubscribe(subscribers)
              subscribers.each do |subscriber|
                patterns = if subscriber.patterns.respond_to?(:keys)
                             subscriber.patterns.keys
                           else
                             subscriber.patterns
                           end
                patterns.each do |pattern|
                  ::ActiveSupport::Notifications.notifier.listeners_for(pattern).each do |listener|
                    if listener.instance_variable_get('@delegate') == subscriber
                      ::ActiveSupport::Notifications.unsubscribe listener
                    end
                  end
                end
                ::ActiveSupport::LogSubscriber.log_subscribers.delete(subscriber)
              end
            end
          end
        end
      end
    end
  end
end
