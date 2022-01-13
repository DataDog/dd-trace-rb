# typed: false

module Datadog
  module Contrib
    # Defines registerable behavior for integrations
    module Registerable
      def self.included(base)
        base.extend(ClassMethods)
        base.include(InstanceMethods)
      end

      # Class methods for registerable behavior
      # @public_api
      module ClassMethods
        # Registers this integration in the global tracer registry.
        # Once registered, this integration can be activated with:
        #
        # ```
        # Datadog::Tracing.configure do |c|
        #   c.use :name
        # end
        # ```
        #
        # @param [Symbol] name integration name. Used during activation.
        # @param [Datadog::Contrib::Registry] registry a custom registry. Defaults to the global tracing registry.
        # @param [Boolean] auto_patch will this integration be activated during
        #   {file:docs/AutoInstrumentation.md Auto Instrumentation}?
        # @param [Hash] options additional keyword options passed to the initializer of
        #   a custom {Registerable} instrumentation
        # @see Datadog::Contrib::Integration
        def register_as(name, registry: Datadog::Contrib::REGISTRY, auto_patch: false, **options)
          registry.add(name, new(name, **options), auto_patch)
        end
      end

      # Instance methods for registerable behavior
      module InstanceMethods
        attr_reader \
          :name

        def initialize(name, **options)
          @name = name
        end
      end
    end
  end
end
