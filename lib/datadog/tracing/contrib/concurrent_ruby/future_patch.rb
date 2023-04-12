require_relative 'context_composite_executor_service'

module Datadog
  module Tracing
    module Contrib
      module ConcurrentRuby
        # This patches the Future - to wrap executor service using ContextCompositeExecutorService
        module FuturePatch
          def self.included(base)
            base.class_eval do
              alias_method :ns_initialize_without_datadog, :ns_initialize
              remove_method(:ns_initialize)

              def ns_initialize(value, opts)
                ns_initialize_without_datadog(value, opts)

                @executor = ContextCompositeExecutorService.new(@executor)
              end
            end
          end
        end
      end
    end
  end
end
