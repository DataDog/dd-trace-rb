# frozen_string_literal: true

require_relative "base"
require_relative "../configuration_snapshot"

module Datadog
  module Core
    module Telemetry
      module Event
        # Telemetry class for the 'app-started' event
        class AppStarted < Base
          def initialize(components:)
            # To not hold a reference to the component tree, generate
            # the event payload here in the constructor.
            #
            # Important: do not store data that contains (or is derived from)
            # the runtime_id or sequence numbers.
            # This event is reused when a process forks, but in the
            # child process the runtime_id would be different and sequence
            # number is reset.
            @configuration = ConfigurationSnapshot.call(components.settings, components.agent_settings)
            @install_signature = install_signature(components.settings)
            @products = products(components)
          end

          def type
            "app-started"
          end

          def payload
            {
              products: @products,
              configuration: @configuration,
              install_signature: @install_signature,
              # DEV: Not implemented yet
              # error: error, # Start-up errors
            }
          end

          # Whether the event is actually the app-started event.
          # For the app-started event we follow up by sending
          # app-dependencies-loaded, if the event is
          # app-client-configuration-change we don't send
          # app-dependencies-loaded.
          def app_started?
            true
          end

          private

          def products(components)
            # @type var products: telemetry_products
            products = {
              appsec: {
                enabled: !!components.appsec,
              },
              profiler: {
                enabled: !!components.profiler,
              },
              dynamic_instrumentation: {
                # With always-build, the DI component is constructed by
                # default (when the runtime supports DI, RC is available, and
                # DI is not explicitly disabled) regardless of whether the
                # customer turned DI on. Its presence therefore no longer
                # indicates the enabled state. started? reflects whether DI was
                # actually enabled by env var or by implicit enablement via
                # remote config.
                enabled: components.dynamic_instrumentation&.started? || false,
              },
            }

            if (unsupported_reason = Datadog::Profiling.unsupported_reason)
              products[:profiler][:error] = {
                code: 1, # Error code. 0 if no error.
                message: unsupported_reason,
              }
            end

            products
          end

          def install_signature(settings)
            {
              install_id: settings.dig("telemetry", "install_id"),
              install_type: settings.dig("telemetry", "install_type"),
              install_time: settings.dig("telemetry", "install_time"),
            }
          end
        end
      end
    end
  end
end
