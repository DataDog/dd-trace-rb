require 'ddtrace/contrib/concurrent_ruby/context_composite_executor_service'

module Datadog
  module Contrib
    module ConcurrentRuby
      # This patches the Future - to wrap executor service using ContextCompositeExecutorService
      module FuturePatch
        def self.included(base)
          if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.0.0')
            base.class_eval do
              alias_method :ns_initialize_without_datadog, :ns_initialize
              remove_method :ns_initialize
              include InstanceMethods
            end
          else
            base.send(:prepend, InstanceMethods)
          end
        end

        # Ruby 1.9.+ Compatibility
        module InstanceMethodsCompatibility
          def ns_initialize(value, opts)
            ns_initialize_without_datadog(value, opts)
          end
        end

        # Methods patched into Future
        module InstanceMethods
          extend InstanceMethodsCompatibility if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.0.0')

          def ns_initialize(value, opts)
            super
            @executor = ContextCompositeExecutorService.new(@executor)
          end

          def datadog_configuration
            Datadog.configuration[:concurrent_ruby]
          end
        end
      end
    end
  end
end
