# frozen_string_literal: true

require_relative '../utils/only_once'

module Datadog
  module Core
    module Configuration
      # Import config from config files (fleet automation)
      module StableConfig
        LOG_ONLY_ONCE = Utils::OnlyOnce.new

        def self.extract_configuration
          if (libdatadog_api_failure = Datadog::Core::LIBDATADOG_API_FAILURE)
            Datadog.config_init_logger.debug("Cannot enable stable config: #{libdatadog_api_failure}")
            return {}
          end
          Configurator.new.get
        end

        def self.configuration
          @configuration ||= StableConfig.extract_configuration
        end

        def self.log_result(logger)
          LOG_ONLY_ONCE.run do
            logger.debug(configuration[:logs]) if configuration[:logs]
          end
        end
      end
    end
  end
end
