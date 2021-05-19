require 'set'
require 'ddtrace/contrib/registry'

module Datadog
  module Contrib
    # Extensions that can be added to the base library
    # Adds registry, configuration access for integrations.
    module Extensions
      def self.extended(base)
        Datadog.extend(Helpers)
        Datadog.extend(Configuration)
        Datadog::Configuration::Settings.include(Configuration::Settings)
      end

      # Helper methods for Datadog module.
      module Helpers
        def registry
          configuration.registry
        end
      end

      # Configuration methods for Datadog module.
      module Configuration
        def configure(target = configuration, opts = {})
          # Reconfigure core settings
          super

          # Activate integrations
          if target.respond_to?(:integrations_pending_activation)
            reduce_verbosity = target.respond_to?(:reduce_verbosity?) ? target.reduce_verbosity? : false
            target.integrations_pending_activation.each do |integration|
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

            target.integrations_pending_activation.clear
          end

          target
        end

        # Extensions for Datadog::Configuration::Settings
        module Settings
          InvalidIntegrationError = Class.new(StandardError)

          def self.included(base)
            # Add the additional options to the global configuration settings
            base.instance_eval do
              option :registry, default: Registry.new
            end
          end

          # For the provided `integration_name`, resolves a matching configuration
          # for the provided integration from an integration-specific `key`.
          #
          # How the matching is performed is integration-specific.
          #
          # @param [Symbol] integration_name the integration name
          # @param [Object] key the integration-specific lookup key
          # @return [Datadog::Contrib::Configuration::Settings]
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
          # @return [Datadog::Contrib::Configuration::Settings]
          def configuration(integration_name, describes = nil)
            integration = fetch_integration(integration_name)
            integration.configuration(describes) unless integration.nil?
          end

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

          alias_method :use, :instrument

          def integrations_pending_activation
            @integrations_pending_activation ||= Set.new
          end

          def instrumented_integrations
            @instrumented_integrations ||= {}
          end

          def reset!
            instrumented_integrations.clear
            super
          end

          def fetch_integration(name)
            registry[name] ||
              raise(InvalidIntegrationError, "'#{name}' is not a valid integration.")
          end

          def reduce_verbosity?
            defined?(@reduce_verbosity) ? @reduce_verbosity : false
          end

          def reduce_log_verbosity
            @reduce_verbosity ||= true
          end
        end
      end
    end
  end
end
