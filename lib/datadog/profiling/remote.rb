# frozen_string_literal: true

require_relative "../core/telemetry/configuration_value"

module Datadog
  module Profiling
    # Provides the interface expected by the core Remote subsystem to receive
    # profiling configuration.
    #
    # Profiling has no RC product of its own: its settings arrive as fields of
    # the APM_TRACING payload and are routed here by
    # {Datadog::Tracing::Remote.apply_lib_config}.
    #
    # @api private
    module Remote
      ENABLED_KEY = "profiling_enabled"
      NO_SIGNALS_WORKAROUND_KEY = "profiling_no_signals_workaround_enabled"

      ENV_ENABLED = "DD_PROFILING_ENABLED"
      ENV_NO_SIGNALS_WORKAROUND_ENABLED = "DD_PROFILING_NO_SIGNALS_WORKAROUND_ENABLED"

      # TODO: libdatadog's RemoteConfigCapabilities enum has no bit for profiling
      # enablement (highest allocated is 48, LlmObsActivation), so the backend
      # never sends the keys above and this path stays dormant. To turn it on:
      # register ApmTracingEnableProfiling in that enum, then list the bit here
      # and gate it on Profiling.supported?, so that runtimes which cannot
      # profile (JRuby, missing native extension) don't advertise it.
      CAPABILITIES = [].freeze

      class << self
        def capabilities
          CAPABILITIES
        end

        # Applies the profiling fields of a merged APM_TRACING lib_config,
        # restarting the profiler if either resolved setting changed. Returns
        # env var/value pairs for telemetry.
        #
        # Runs on the remote-config worker thread.
        def apply_lib_config(lib_config)
          settings = Datadog.configuration
          before = profiling_settings(settings)

          # @type var env_vars: ::Array[[::String, untyped]]
          env_vars = [
            [ENV_ENABLED, apply_option(settings.profiling, :enabled, lib_config[ENABLED_KEY])],
            [
              ENV_NO_SIGNALS_WORKAROUND_ENABLED,
              apply_option(
                settings.profiling.advanced,
                :no_signals_workaround_enabled,
                lib_config[NO_SIGNALS_WORKAROUND_KEY],
              ),
            ],
          ]

          restart_profiler if profiling_settings(settings) != before

          env_vars
        end

        private

        # A nil value means the field was absent from every merged config, which
        # reverts the setting to whatever the customer configured locally.
        def apply_option(configuration_object, setting_key, value)
          precedence = Core::Configuration::Option::Precedence::REMOTE_CONFIGURATION

          if value.nil?
            configuration_object.unset_option(setting_key, precedence: precedence)
          else
            configuration_object.set_option(setting_key, value, precedence: precedence)
          end

          Core::Telemetry::ConfigurationValue.convert(value)
        end

        # Resolved values, not the raw lib_config fields: a field absent from RC
        # falls back to the local value, so only these tell us whether the
        # profiler would now be built differently.
        def profiling_settings(settings)
          [settings.profiling.enabled, settings.profiling.advanced.no_signals_workaround_enabled]
        end

        def restart_profiler
          # allow_initialization: false to avoid building the component tree
          # from the remote-config worker thread.
          Datadog.send(:components, allow_initialization: false)&.reconfigure_profiler
        end
      end
    end
  end
end
