# frozen_string_literal: true

require_relative "source/resolution"

module Datadog
  module OpenFeature
    module Configuration
      # Resolves the effective Feature Flags configuration source.
      module Source
        AGENTLESS = "agentless"
        REMOTE_CONFIG = "remote_config"
        OFFLINE = "offline"

        def self.resolve(settings, logger: Datadog.logger)
          legacy_enabled = settings.enabled
          configured_source = settings.configuration_source
          source = if !settings.using_default?(:configuration_source) && !configured_source.empty?
            resolve_explicit_source(configured_source, logger)
          elsif !settings.using_default?(:feature_flags_enabled)
            AGENTLESS
          elsif !settings.using_default?(:enabled)
            legacy_enabled ? REMOTE_CONFIG : OFFLINE
          else
            AGENTLESS
          end

          Resolution.new(enabled: settings.feature_flags_enabled && source != OFFLINE, source: source)
        end

        def self.resolve_explicit_source(source, logger)
          return source if source == AGENTLESS || source == REMOTE_CONFIG || source == OFFLINE

          logger.warn("Unsupported Feature Flags configuration source; Feature Flags are disabled")
          OFFLINE
        end
        private_class_method :resolve_explicit_source
      end
    end
  end
end
