# frozen_string_literal: true

module Datadog
  module Core
    module Configuration
      # Import config from config files (fleet automation)
      module StableConfig
        module_function

        def extract_configuration
          if (libdatadog_api_failure = Datadog::Core::LIBDATADOG_API_FAILURE)
            Datadog.logger.debug("Cannot enable stable config: #{libdatadog_api_failure}")
            return {}
          end
          native_configurator = Configurator.new
          native_configurator.get
        end

        def configuration
          @configuration ||= StableConfig.extract_configuration
        end
      end
    end
  end
end
