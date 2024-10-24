# frozen_string_literal: true

require_relative '../configuration/ext'

module Datadog
  module Core
    module Crashtracking
      # This module provides a method to resolve the base URL of the agent
      module AgentBaseUrl
        def self.resolve(agent_settings)
          case agent_settings.adapter
          when Datadog::Core::Configuration::Ext::Agent::HTTP::ADAPTER
            "#{agent_settings.ssl ? 'https' : 'http'}://#{agent_settings.hostname}:#{agent_settings.port}/"
          when Datadog::Core::Configuration::Ext::Agent::UnixSocket::ADAPTER
            "unix://#{agent_settings.uds_path}"
          end
        end
      end
    end
  end
end
