# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module ActiveJob
        # Active Job log injection wrapped around job execution
        module LogInjection
          # Active Job 4 / 5 don't execute `perform_now` at the right point, so we do best effort log correlation tagging
          module AroundPerformPatch
            def self.included(base)
              base.class_eval do
                around_perform do |_, block|
                  if Datadog.configuration.tracing.log_injection && logger.respond_to?(:tagged)
                    logger.tagged(Tracing.log_correlation, &block)
                  else
                    block.call
                  end
                end
              end
            end
          end

          # Active Job 6+ executes `perform_now` at the right point, so we can provide better log correlation tagging
          module PerformNowPatch
            def perform_now
              if Datadog.configuration.tracing.log_injection && logger.respond_to?(:tagged)
                logger.tagged(Tracing.log_correlation) { super }
              else
                super
              end
            end
          end
        end
      end
    end
  end
end
