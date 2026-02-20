# frozen_string_literal: true

require_relative 'app_started'

module Datadog
  module Core
    module Telemetry
      module Event
        # Telemetry class for the 'app-extended-heartbeat' event
        # This event is sent periodically (default: every 24 hours) as a failsafe
        # to reconstruct application records in case of catastrophic data failure.
        # It includes configuration, dependencies, and integrations but excludes
        # products and install_signature which are only sent in app-started.
        class AppExtendedHeartbeat < AppStarted
          def initialize(components:)
            super(components: components)
          end

          def type
            'app-extended-heartbeat'
          end

          def payload
            {
              configuration: @configuration,
              dependencies: dependencies,
              integrations: integrations,
            }
          end

          def app_started?
            false
          end

          private

          def dependencies
            Gem.loaded_specs.collect do |name, gem|
              {
                name: name,
                version: gem.version.to_s,
              }
            end
          end

          def integrations
            instrumented_integrations = Datadog.configuration.tracing.instrumented_integrations
            Datadog.registry.map do |integration|
              is_instrumented = instrumented_integrations.include?(integration.name)

              is_enabled = is_instrumented && integration.klass.patcher.patch_successful

              version = integration.klass.class.version&.to_s

              res = {
                name: integration.name.to_s,
                enabled: is_enabled,
                version: version,
                compatible: integration.klass.class.compatible?,
                error: (patch_error(integration) if is_instrumented && !is_enabled),
              }
              res.reject! { |_, v| v.nil? }
              res
            end
          end

          def patch_error(integration)
            patch_error_result = integration.klass.patcher.patch_error_result
            return patch_error_result.compact.to_s if patch_error_result

            "Available?: #{integration.klass.class.available?}" \
            ", Loaded? #{integration.klass.class.loaded?}" \
            ", Compatible? #{integration.klass.class.compatible?}" \
            ", Patchable? #{integration.klass.class.patchable?}"
          end
        end
      end
    end
  end
end
