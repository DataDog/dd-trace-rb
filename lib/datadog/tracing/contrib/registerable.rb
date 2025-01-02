# frozen_string_literal: true

module Datadog
  module Tracing
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
          # Datadog.configure do |c|
          #   c.tracing.instrument :name
          # end
          # ```
          #
          # @param [Symbol] name integration name. Used during activation.
          # @param [Datadog::Tracing::Contrib::Registry] registry a custom registry.
          #        Defaults to the global tracing registry.
          # @param [Boolean] auto_patch will this integration be activated during
          #   {file:docs/AutoInstrumentation.md Auto Instrumentation}?
          # @param [Hash] options additional keyword options passed to the initializer of
          #   a custom {Registerable} instrumentation
          # @see Datadog::Tracing::Contrib::Integration
          def register_as(name, registry: Contrib::REGISTRY, auto_patch: false, **options)
            registry.add(name, new(name, **options), auto_patch)
          end

          # Registers this `alias_name` in the global tracer registry as an alias of `original_name`.
          # Using `alias_name` or `original_name` become interchangeable.
          # The configuration object is shared between the two names.
          # The patcher will only run once if both are activated.
          def register_as_alias(original_name, alias_name, registry: Contrib::REGISTRY)
            original = registry[original_name]
            raise ArgumentError, "integration '#{original_name}' not registered" unless original

            registry.add(alias_name, original, false)
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
end
