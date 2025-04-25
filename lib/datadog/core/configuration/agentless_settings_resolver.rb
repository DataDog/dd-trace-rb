# frozen_string_literal: true

require 'uri'

require_relative 'agent_settings_resolver'

module Datadog
  module Core
    module Configuration
      # Agent settings resolver for agentless operations (currently, telemetry
      # in agentless mode).
      #
      # The terminology gets a little confusing here, but transports communicate
      # with servers which are - for most components in the tracer - the
      # (local) agent. Hence, "agent settings" to refer to where the server
      # is located. Telemetry supports sending to the local agent but also
      # implements agentless mode where it sends directly to Datadog intake
      # endpoints. The agentless mode is configured using different settings,
      # and this class produces AgentSettings instances when in agentless mode.
      class AgentlessSettingsResolver < AgentSettingsResolver

        # To avoid coupling this class to telemetry, the URL override is
        # taken here as a parameter instead of being read out of
        # c.telemetry.agentless_url_override. For the same reason, the
        # +url_override_source+ parameter should be set to the string
        # "c.telemetry.agentless_url_override".
        def self.call(settings, host_prefix:, url_override: nil, url_override_source: nil, logger: Datadog.logger)
          new(settings, host_prefix: host_prefix, url_override: url_override, url_override_source: url_override_source, logger: logger).send(:call)
        end

        private

        attr_reader \
          :host_prefix,
          :url_override,
          :url_override_source

        def initialize(settings, host_prefix:, url_override: nil, url_override_source: nil, logger: Datadog.logger)
          if url_override && url_override_source.nil?
            raise ArgumentError, 'url_override_source must be provided when url_override is provided'
          end

          super(settings, logger: logger)

          @host_prefix = host_prefix
          @url_override = url_override
          @url_override_source = url_override_source
        end

        def hostname
          configured_hostname || "#{host_prefix}.#{settings.site}"
        end

        def configured_hostname
          return @configured_hostname if defined?(@configured_hostname)

          @configured_hostname = if parsed_url
            parsed_url.hostname
          else
            nil
          end

          @configured_hostname = pick_from(
            DetectedConfiguration.new(
              friendly_name: "'c.agent.host'",
              value: settings.agent.host
            ),
            DetectedConfiguration.new(
              friendly_name: "#{Datadog::Core::Configuration::Ext::Agent::ENV_DEFAULT_URL} environment variable",
              value: parsed_http_url&.hostname
            ),
            DetectedConfiguration.new(
              friendly_name: "#{Datadog::Core::Configuration::Ext::Agent::ENV_DEFAULT_HOST} environment variable",
              value: ENV[Datadog::Core::Configuration::Ext::Agent::ENV_DEFAULT_HOST]
            )
          )
        end

        def configured_port
          return @configured_port if defined?(@configured_port)

          @configured_port = if parsed_url
            parsed_url.port
          end

          @configured_port = pick_from(
            try_parsing_as_integer(
              friendly_name: '"c.agent.port"',
              value: settings.agent.port,
            ),
            DetectedConfiguration.new(
              friendly_name: "#{Datadog::Core::Configuration::Ext::Agent::ENV_DEFAULT_URL} environment variable",
              value: parsed_http_url&.port,
            ),
            try_parsing_as_integer(
              friendly_name: "#{Datadog::Core::Configuration::Ext::Agent::ENV_DEFAULT_PORT} environment variable",
              value: ENV[Datadog::Core::Configuration::Ext::Agent::ENV_DEFAULT_PORT],
            )
          )
        end

        # Note that this method should always return true or false
        def ssl?
          if configured_hostname
            configured_ssl || false
          else
            # If no hostname is specified, we are communicating with the
            # default Datadog intake, which uses TLS.
            true
          end
        end

        # Note that this method can return nil
        def configured_ssl
          return @configured_ssl if defined?(@configured_ssl)

          @configured_ssl = if parsed_url
            parsed_url_ssl?
          end
        end

        def port
          if configured_port
            configured_port
          else
            # If no hostname is specified, we are communicating with the
            # default Datadog intake, which exists on port 443.
            443
          end
        end

        def configured_uds_path
          # We do not permit UDS, see the note under #can_use_uds?.
          nil
        end

        def can_use_uds?
          # While in theory agentless transport could communicate via UDS,
          # in practice "agentless" means we are communicating with Datadog
          # infrastructure which is always remote.
          false
        end

        def parsed_url
          return @parsed_url if defined?(@parsed_url)

          @parsed_url =
            if @url_override
              parsed = URI.parse(@url_override)

              # Agentless URL should never refer to a UDS?
              if http_scheme?(parsed) || unix_scheme?(parsed)
                parsed
              else
                # rubocop:disable Layout/LineLength
                log_warning(
                  "Invalid URI scheme '#{parsed.scheme}' for #{url_override_source} " \
                  "environment variable ('#{unparsed_url_from_env}'). " \
                  "Ignoring the contents of #{url_override_source}."
                )
                # rubocop:enable Layout/LineLength

                nil
              end
            end
        end
      end
    end
  end
end
