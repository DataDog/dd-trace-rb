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

        def http_scheme?(uri)
          ['http', 'https'].include?(uri.scheme)
        end

        def unix_scheme?(uri)
          uri.scheme == 'unix'
        end

        def try_parsing_as_integer(value:, friendly_name:)
          value =
            begin
              Integer(value) if value
            rescue ArgumentError, TypeError
              log_warning("Invalid value for #{friendly_name} (#{value.inspect}). Ignoring this configuration.")

              nil
            end

          DetectedConfiguration.new(friendly_name: friendly_name, value: value)
        end

        # Represents a given configuration value and where we got it from
        class DetectedConfiguration
          attr_reader :friendly_name, :value

          def initialize(friendly_name:, value:)
            @friendly_name = friendly_name
            @value = value
            freeze
          end

          def value?
            !value.nil?
          end
        end
        private_constant :DetectedConfiguration
      end
    end
  end
end
