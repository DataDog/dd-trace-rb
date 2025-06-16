# frozen_string_literal: true

require_relative 'ext'

module Datadog
  module Core
    module Configuration
      # Immutable container for the resulting settings
      class AgentSettings
        attr_reader :adapter, :ssl, :hostname, :port, :uds_path, :timeout_seconds

        def initialize(adapter: nil, ssl: nil, hostname: nil, port: nil, uds_path: nil, timeout_seconds: nil)
          @adapter = adapter
          @ssl = ssl
          @hostname = hostname
          @port = port
          @uds_path = uds_path
          @timeout_seconds = timeout_seconds
          freeze
        end

        def url
          case adapter
          when Datadog::Core::Configuration::Ext::Agent::HTTP::ADAPTER
            hostname = self.hostname
            hostname = "[#{hostname}]" if IPV6_REGEXP.match?(hostname)
            "#{ssl ? "https" : "http"}://#{hostname}:#{port}/"
          when Datadog::Core::Configuration::Ext::Agent::UnixSocket::ADAPTER
            "unix://#{uds_path}"
          else
            raise ArgumentError, "Unexpected adapter: #{adapter}"
          end
        end

        def ==(other)
          self.class == other.class &&
            adapter == other.adapter &&
            ssl == other.ssl &&
            hostname == other.hostname &&
            port == other.port &&
            uds_path == other.uds_path &&
            timeout_seconds == other.timeout_seconds
        end
      end
    end
  end
end
