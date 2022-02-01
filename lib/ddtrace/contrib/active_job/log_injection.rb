# typed: false
module Datadog
  module Contrib
    module ActiveJob
      # Active Job log injection wrapped around job execution
      module LogInjection
        def self.included(base)
          base.class_eval do
            around_perform do |_, block|
              if logger.respond_to?(:tagged)
                logger.tagged(Datadog::Tracing.log_correlation, &block)
              else
                block.call
              end
            end
          end
        end
      end
    end
  end
end
