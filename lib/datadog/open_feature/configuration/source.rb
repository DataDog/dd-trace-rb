# frozen_string_literal: true

require_relative "source/resolution"

module Datadog
  module OpenFeature
    module Configuration
      module Source
        AGENTLESS = "agentless"
        REMOTE_CONFIG = "remote_config"
        OFFLINE = "offline"

        class << self
          def resolve(settings, logger: Datadog.logger)
            source = resolve_source(settings, logger: logger)
            enabled = settings.feature_flags_enabled && source != OFFLINE

            Resolution.new(source, enabled: enabled)
          end

          private

          def resolve_source(settings, logger:)
            configured_source = settings.configuration_source
            if !settings.using_default?(:configuration_source) && !configured_source.empty?
              return configured_source if configured_source == AGENTLESS ||
                configured_source == REMOTE_CONFIG ||
                configured_source == OFFLINE

              logger.warn("Unsupported Feature Flags configuration source; Feature Flags are disabled")
              OFFLINE
            elsif !settings.using_default?(:enabled)
              settings.enabled ? REMOTE_CONFIG : OFFLINE
            else
              AGENTLESS
            end
          end
        end
      end
    end
  end
end
