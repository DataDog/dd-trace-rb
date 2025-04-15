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
        def self.call(settings, url_override: nil, url_override_source: nil, logger: Datadog.logger)
          new(settings, url_override: url_override, url_override_source: url_override_source, logger: logger).send(:call)
        end

        private

        attr_reader \
          :url_override,
          :url_override_source

        def initialize(settings, url_override: nil, url_override_source: nil, logger: Datadog.logger)
          super(settings, logger: logger)
          @url_override = url_override
          @url_override_source = url_override_source
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
          else
            80
          end
        end

        def configured_ssl
          return @configured_ssl if defined?(@configured_ssl)

          @configured_ssl = if parsed_url
            parsed_url_ssl?
          else
            true
          end
        end

        def configured_uds_path
          return @configured_uds_path if defined?(@configured_uds_path)

          @configured_uds_path = if parsed_url
            parsed_url_uds_path
          else
            false
          end
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
