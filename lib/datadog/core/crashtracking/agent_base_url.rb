# frozen_string_literal: true

require_relative '../configuration/ext'

module Datadog
  module Core
    module Crashtracking
      module AgentBaseUrl
        module_function

        def resolve(agent_settings)
          case agent_settings.adapter
          when Datadog::Core::Configuration::Ext::Agent::HTTP::ADAPTER
            "#{agent_settings.ssl ? 'https' : 'http'}://#{agent_settings.hostname}:#{agent_settings.port}/"
          when Datadog::Core::Configuration::Ext::Agent::UnixSocket::ADAPTER
            "unix://#{agent_settings.uds_path}"
          else
            Datadog.logger.warn("Unexpected adapter: #{agent_settings.adapter}")
            nil
          end
        end
      end
    end
  end
end
