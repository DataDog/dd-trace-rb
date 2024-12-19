# frozen_string_literal: true

require_relative '../configuration/ext'

module Datadog
  module Core
    module Crashtracking
      # This module provides a method to resolve the base URL of the agent
      module AgentBaseUrl
        # IPv6 regular expression from
        # https://stackoverflow.com/questions/53497/regular-expression-that-matches-valid-ipv6-addresses
        # Does not match IPv4 addresses.
        IPV6_REGEXP = /\A(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\z)/

        def self.resolve(agent_settings)
          case agent_settings.adapter
          when Datadog::Core::Configuration::Ext::Agent::HTTP::ADAPTER
            hostname = agent_settings.hostname
            if hostname =~ IPV6_REGEXP
              hostname = "[#{hostname}]"
            end
            "#{agent_settings.ssl ? 'https' : 'http'}://#{hostname}:#{agent_settings.port}/"
          when Datadog::Core::Configuration::Ext::Agent::UnixSocket::ADAPTER
            "unix://#{agent_settings.uds_path}"
          end
        end
      end
    end
  end
end
