# typed: false
require 'forwardable'
require 'set'

require 'datadog/core/configuration/settings'
require 'datadog/tracing/contrib'

module Datadog
  module Tracing
    module Contrib
      # Extensions that can be added to the base library
      # Adds registry, configuration access for integrations.
      #
      # DEV: The Registry should probably be part of the core tracer
      # as it represents a global tracer repository that is strongly intertwined
      # with the tracer lifecycle and deeply modifies the tracer initialization
      # process.
      # Most of this file should probably live inside the tracer core.
      module Extensions
        def self.extend!
          Datadog.singleton_class.prepend Helpers
          Datadog.singleton_class.prepend Configuration
          Core::Configuration::Settings.include Configuration::Settings
        end

        # Helper methods for Datadog module.
        module Helpers
          # The global integration registry.
          #
          # This registry holds a reference to all integrations available
          # to the tracer.
          #
          # Integrations registered in the {.registry} can be activated as follows:
          #
          # ```
          # Datadog.configure do |c|
          #   c.tracing.instrument :my_registered_integration, **my_options
          # end
          # ```
          #
          # New integrations can be registered by implementing the {Datadog::Tracing::Contrib::Integration} interface.
          #
          # @return [Datadog::Tracing::Contrib::Registry]
          # @!attribute [r] registry
          # @public_api
          def registry
            Contrib::REGISTRY
          end
        end

        # Configuration methods for Datadog module.
        module Configuration
          # TODO: Is is not possible to separate this configuration method
          # TODO: from core ddtrace parts ()e.g. the registry).
          # TODO: Today this method sits here in the `Datadog::Tracing::Contrib::Extensions` namespace
          # TODO: but cannot empirically constraints to the contrib domain only.
          # TODO: We should promote most of this logic to core parts of ddtrace.
          def configure(&block)
            # Reconfigure core settings
            super(&block)

            # Activate integrations
            configuration = self.configuration

            if configuration.respond_to?(:integrations_pending_activation)
              reduce_verbosity = configuration.respond_to?(:reduce_verbosity?) ? configuration.reduce_verbosity? : false
              configuration.integrations_pending_activation.each do |integration|
                next unless integration.respond_to?(:patch)

                # integration.patch returns either true or a hash of details on why patching failed
                patch_results = integration.patch

                next if patch_results == true

                # if patching failed, only log output if verbosity is unset
                # or if patching failure is due to compatibility or integration specific reasons
                next unless !reduce_verbosity ||
                            ((patch_results[:available] && patch_results[:loaded]) &&
                            (!patch_results[:compatible] || !patch_results[:patchable]))

                desc = "Available?: #{patch_results[:available]}"
                desc += ", Loaded? #{patch_results[:loaded]}"
                desc += ", Compatible? #{patch_results[:compatible]}"
                desc += ", Patchable? #{patch_results[:patchable]}"

                Datadog.logger.warn("Unable to patch #{patch_results[:name]} (#{desc})")
              end

              configuration.integrations_pending_activation.clear
            end

            configuration
          end

          # Extensions for Datadog::Core::Configuration::Settings
          # @public_api
          module Settings
            InvalidIntegrationError = Class.new(StandardError)

            # For the provided `integration_name`, resolves a matching configuration
            # for the provided integration from an integration-specific `key`.
            #
            # How the matching is performed is integration-specific.
            #
            # @example
            #   Datadog.configuration[:integration_name]
            # @example
            #   Datadog.configuration[:integration_name][:sub_configuration]
            # @param [Symbol] integration_name the integration name
            # @param [Object] key the integration-specific lookup key
            # @return [Datadog::Tracing::Contrib::Configuration::Settings]
            def [](integration_name, key = :default)
              integration = fetch_integration(integration_name)
              integration.resolve(key) unless integration.nil?
            end

            # For the provided `integration_name`, retrieves a configuration previously
            # stored by `#instrument`. Specifically, `describes` should be
            # the same value provided in the `describes:` option for `#instrument`.
            #
            # If no `describes` value is provided, the default configuration is returned.
            #
            # @param [Symbol] integration_name the integration name
            # @param [Object] describes the previously configured `describes:` object. If `nil`,
            #   fetches the default configuration
            # @return [Datadog::Tracing::Contrib::Configuration::Settings]
            # @!visibility private
            def configuration(integration_name, describes = nil)
              integration = fetch_integration(integration_name)
              integration.configuration(describes) unless integration.nil?
            end

            # @!visibility private
            def integrations_pending_activation
              @integrations_pending_activation ||= Set.new
            end

            # @!visibility private
            def instrumented_integrations
              @instrumented_integrations ||= {}
            end

            # @!visibility private
            def reset!
              instrumented_integrations.clear
              super
            end

            # @!visibility private
            def fetch_integration(name)
              Contrib::REGISTRY[name] ||
                raise(InvalidIntegrationError, "'#{name}' is not a valid integration.")
            end

            # @!visibility private
            def reduce_verbosity?
              defined?(@reduce_verbosity) ? @reduce_verbosity : false
            end

            def reduce_log_verbosity
              @reduce_verbosity ||= true
            end

            private

            def instrument(integration_name, options = {}, &block)
              integration = fetch_integration(integration_name)

              unless integration.nil? || !integration.default_configuration.enabled
                configuration_name = options[:describes] || :default
                filtered_options = options.reject { |k, _v| k == :describes }
                integration.configure(configuration_name, filtered_options, &block)
                instrumented_integrations[integration_name] = integration

                # Add to activation list
                integrations_pending_activation << integration
              end
            end
          end
        end
      end
    end
  end

  # Load built-in Datadog integrations
  Tracing::Contrib::Extensions.extend!
end
