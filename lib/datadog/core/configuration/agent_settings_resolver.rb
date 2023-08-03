module Datadog
  module Core
    module Configuration
      module AgentSettingsResolver
        AgentSettings = \
          Struct.new(
            :adapter,
            :ssl,
            :hostname,
            :port,
            :uds_path,
            :timeout_seconds,
            :deprecated_for_removal_transport_configuration_proc,
          ) do
            def initialize(
              adapter:,
              ssl:,
              hostname:,
              port:,
              uds_path:,
              timeout_seconds:,
              deprecated_for_removal_transport_configuration_proc:
            )
              super(
                adapter,
                ssl,
                hostname,
                port,
                uds_path,
                timeout_seconds,
                deprecated_for_removal_transport_configuration_proc
              )
              freeze
            end
          end

        #TODO: EK - This feels dirty somehow. Get feedback.
        def log_warning(message)
          @logger.warn(message) if @logger
        end
      end
    end
  end
end
