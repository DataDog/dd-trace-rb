require 'set'
require 'ddtrace/contrib/registry'

module Datadog
  module Contrib
    # Extensions that can be added to the base library
    # Adds registry, configuration access for integrations.
    module Extensions
      def self.extended(base)
        Datadog.send(:extend, Helpers)
        Datadog.send(:extend, Configuration)
        Datadog::Configuration::Settings.send(:include, Configuration::Settings)
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
              next unless patch_results.is_a?(Hash)
              # if patching failed, only log output if verbosity is unset
              # or if patching failure is due to compatibility or integration specific reasons
              if !reduce_verbosity ||
                 ((patch_results['available'] && patch_results['loaded']) &&
                  (!patch_results['compatible'] || !patch_results['patchable']))
                desc = "Available?: #{patch_results['available']}"
                desc += ", Loaded? #{patch_results['loaded']}"
                desc += ", Compatible? #{patch_results['compatible']}"
                desc += ", Patchable? #{patch_results['patchable']}"

                Datadog.logger.warn("Unable to patch #{patch_results['name']} (#{desc})")
              end
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

          def [](integration_name, configuration_name = :default)
            integration = fetch_integration(integration_name)
            integration.configuration(configuration_name) unless integration.nil?
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
            @reduce_verbosity
          end

          def reduce_log_verbosity
            @reduce_verbosity ||= true
          end
        end
      end
    end
  end
end
