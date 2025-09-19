# frozen_string_literal: true

module Datadog
  module Core
    module Configuration
      # Import config from config files (fleet automation)
      module StableConfig
        def self.extract_configuration
          if (libdatadog_api_failure = Datadog::Core::LIBDATADOG_API_FAILURE)
            Datadog.config_init_logger.debug("Cannot enable stable config: #{libdatadog_api_failure}")
            return {}
          end
          config = Configurator.new.get
          # Take into account stable config values for DD_TRACE_DEBUG
          if config[:logs]
            # Priority : Fleet > Environment > Local
            debug_source_value =
              config.dig(:fleet, :config, Ext::Diagnostics::ENV_DEBUG_ENABLED) ||
              DATADOG_ENV[Ext::Diagnostics::ENV_DEBUG_ENABLED] ||
              config.dig(:local, :config, Ext::Diagnostics::ENV_DEBUG_ENABLED) ||
              'false'
            Datadog.config_init_logger(debug_source_value).debug(config[:logs])
          end
          config
        end

        def self.configuration
          @configuration ||= StableConfig.extract_configuration
        end
      end
    end
  end
end
