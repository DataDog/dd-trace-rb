# frozen_string_literal: true

module Datadog
  module OpenFeature
    module Configuration
      # A settings class for the OpenFeature component.
      module Settings
        AGENTLESS_SOURCE = "agentless"
        REMOTE_CONFIG_SOURCE = "remote_config"
        OFFLINE_SOURCE = "offline"

        DEFAULT_POLL_INTERVAL_SECONDS = 30
        DEFAULT_REQUEST_TIMEOUT_SECONDS = 5
        DEFAULT_INITIALIZATION_TIMEOUT_MS = 30_000

        MAX_POLL_INTERVAL_SECONDS = 3600
        MAX_REQUEST_TIMEOUT_SECONDS = 300
        MAX_INITIALIZATION_TIMEOUT_MS = 2_147_483_647

        def self.parse_integer(value, default:, setting:)
          Integer(value, 10)
        rescue ArgumentError
          Datadog.logger.warn("#{setting} must be an integer; using the default")
          default
        end

        def self.enabled?(settings)
          settings.feature_flags_enabled && settings.configuration_source != OFFLINE_SOURCE
        end

        def self.remote_configuration?(settings)
          enabled?(settings) && settings.configuration_source == REMOTE_CONFIG_SOURCE
        end

        def self.extended(base)
          base = base.singleton_class unless base.is_a?(Class)
          add_settings!(base)
        end

        def self.add_settings!(base)
          base.class_eval do
            # Steep does not update `self` for this `class_eval` block.
            # @type self: Datadog::Core::Configuration::Base::_DslContext
            settings :open_feature do
              # Legacy switch. When the stable settings are unset, true keeps existing
              # adopters on Remote Configuration and false disables the provider.
              option :enabled do |o|
                o.type :bool
                o.env "DD_EXPERIMENTAL_FLAGGING_PROVIDER_ENABLED"
                o.default false
                o.after_set do |_, _, precedence|
                  next if precedence == Core::Configuration::Option::Precedence::DEFAULT

                  Datadog.logger.warn(
                    "DD_EXPERIMENTAL_FLAGGING_PROVIDER_ENABLED is deprecated; use " \
                    "DD_FEATURE_FLAGS_ENABLED and DD_FEATURE_FLAGS_CONFIGURATION_SOURCE instead"
                  )
                end
              end

              option :feature_flags_enabled do |o|
                o.type :bool
                o.env "DD_FEATURE_FLAGS_ENABLED"
                o.default true
              end

              option :configuration_source do |o|
                o.type :string
                o.env "DD_FEATURE_FLAGS_CONFIGURATION_SOURCE"
                o.env_parser do |value|
                  normalized = value.strip.downcase
                  normalized.empty? ? nil : normalized
                end
                o.default do
                  if !using_default?(:feature_flags_enabled)
                    Settings::AGENTLESS_SOURCE
                  elsif !using_default?(:enabled)
                    (get_option(:enabled) == true) ? Settings::REMOTE_CONFIG_SOURCE : Settings::OFFLINE_SOURCE
                  else
                    Settings::AGENTLESS_SOURCE
                  end
                end
                o.setter do |value|
                  normalized = value.to_s.strip.downcase
                  if normalized == Settings::AGENTLESS_SOURCE ||
                      normalized == Settings::REMOTE_CONFIG_SOURCE ||
                      normalized == Settings::OFFLINE_SOURCE
                    normalized
                  else
                    Datadog.logger.warn(
                      "Unsupported Feature Flags configuration source; no configuration will be delivered"
                    )
                    Settings::OFFLINE_SOURCE
                  end
                end
                o.helper(:configuration_source=) do |value|
                  if value.is_a?(String) && value.strip.empty?
                    unset_option(:configuration_source)
                  else
                    set_option(:configuration_source, value)
                  end
                end
              end

              option :agentless_base_url do |o|
                o.type :string, nilable: true
                o.env "DD_FEATURE_FLAGS_CONFIGURATION_SOURCE_AGENTLESS_BASE_URL"
                o.skip_telemetry true
                o.env_parser do |value|
                  stripped = value.strip
                  stripped.empty? ? nil : stripped
                end
                o.setter do |value|
                  next unless value

                  stripped = value.to_s.strip
                  stripped.empty? ? nil : stripped
                end
              end

              option :agentless_poll_interval_seconds do |o|
                o.type :int
                o.env "DD_FEATURE_FLAGS_CONFIGURATION_SOURCE_AGENTLESS_POLL_INTERVAL_SECONDS"
                o.env_parser do |value|
                  Settings.parse_integer(
                    value,
                    default: Settings::DEFAULT_POLL_INTERVAL_SECONDS,
                    setting: "Feature Flags agentless poll interval",
                  )
                end
                o.default Settings::DEFAULT_POLL_INTERVAL_SECONDS
                o.setter do |value|
                  integer_value = value.to_s.to_i
                  if integer_value > 0 && integer_value <= Settings::MAX_POLL_INTERVAL_SECONDS
                    integer_value
                  else
                    Datadog.logger.warn(
                      "Feature Flags agentless poll interval must be within (0, " \
                      "#{Settings::MAX_POLL_INTERVAL_SECONDS}]; using the default"
                    )
                    Settings::DEFAULT_POLL_INTERVAL_SECONDS
                  end
                end
              end

              option :agentless_request_timeout_seconds do |o|
                o.type :int
                o.env "DD_FEATURE_FLAGS_CONFIGURATION_SOURCE_AGENTLESS_REQUEST_TIMEOUT_SECONDS"
                o.env_parser do |value|
                  Settings.parse_integer(
                    value,
                    default: Settings::DEFAULT_REQUEST_TIMEOUT_SECONDS,
                    setting: "Feature Flags agentless request timeout",
                  )
                end
                o.default Settings::DEFAULT_REQUEST_TIMEOUT_SECONDS
                o.setter do |value|
                  integer_value = value.to_s.to_i
                  if integer_value > 0 && integer_value <= Settings::MAX_REQUEST_TIMEOUT_SECONDS
                    integer_value
                  else
                    Datadog.logger.warn(
                      "Feature Flags agentless request timeout must be within (0, " \
                      "#{Settings::MAX_REQUEST_TIMEOUT_SECONDS}]; using the default"
                    )
                    Settings::DEFAULT_REQUEST_TIMEOUT_SECONDS
                  end
                end
              end

              option :initialization_timeout_ms do |o|
                o.type :int
                o.env "DD_EXPERIMENTAL_FLAGGING_PROVIDER_INITIALIZATION_TIMEOUT_MS"
                o.env_parser do |value|
                  Settings.parse_integer(
                    value,
                    default: Settings::DEFAULT_INITIALIZATION_TIMEOUT_MS,
                    setting: "Feature Flags provider initialization timeout",
                  )
                end
                o.default Settings::DEFAULT_INITIALIZATION_TIMEOUT_MS
                o.setter do |value|
                  integer_value = value.to_s.to_i
                  if integer_value > 0 && integer_value <= Settings::MAX_INITIALIZATION_TIMEOUT_MS
                    integer_value
                  else
                    Datadog.logger.warn(
                      "Feature Flags provider initialization timeout must be within (0, " \
                      "#{Settings::MAX_INITIALIZATION_TIMEOUT_MS}]; using the default"
                    )
                    Settings::DEFAULT_INITIALIZATION_TIMEOUT_MS
                  end
                end
              end

              # Opt-in gate for APM feature-flag span enrichment. When enabled,
              # the provider attaches `ffe_*` tags to the local root APM span on
              # finish. Distinct from `:enabled` (the provider gate) and off by
              # default so it can be rolled out independently.
              #
              # TODO: benchmark the per-span-finish overhead on a high-span-count
              # trace with this gate on before enabling it by default.
              option :span_enrichment_enabled do |o|
                o.type :bool
                o.env "DD_EXPERIMENTAL_FLAGGING_PROVIDER_SPAN_ENRICHMENT_ENABLED"
                o.default false
              end

              # Killswitch for the EVP `flagevaluation` emission path only. Default on; when
              # disabled the existing OTel `feature_flag.evaluations` metric is unaffected.
              option :evaluation_counts_enabled do |o|
                o.type :bool
                o.env "DD_FLAGGING_EVALUATION_COUNTS_ENABLED"
                o.default true
              end
            end
          end
        end
      end
    end
  end
end
