# frozen_string_literal: true

require_relative '../../configuration/settings'
require_relative '../../transport/ext'
require_relative 'env'
require_relative 'ext'
require_relative 'adapters/net'

module Datadog
  module Core
    module Telemetry
      module Http
        # Class to send telemetry data to Telemetry API
        # Currently only supports the HTTP protocol.
        class Transport
          attr_reader \
            :host,
            :port,
            :ssl,
            :path

          def initialize
            agent_settings = Configuration::AgentSettingsResolver.call(Datadog.configuration)
            @host = agent_settings.hostname
            @port = agent_settings.port
            @ssl = false
            @path = Http::Ext::AGENT_ENDPOINT
          end

          def request(request_type:, payload:)
            env = Http::Env.new
            env.path = @path
            env.body = payload
            env.headers = headers(request_type: request_type)
            adapter.post(env)
          end

          private

          def headers(request_type:, api_version: Http::Ext::API_VERSION)
            {
              Core::Transport::Ext::HTTP::HEADER_DD_INTERNAL_UNTRACED_REQUEST => '1',
              Ext::HEADER_CONTENT_TYPE => Http::Ext::CONTENT_TYPE_APPLICATION_JSON,
              Ext::HEADER_DD_TELEMETRY_API_VERSION => api_version,
              Ext::HEADER_DD_TELEMETRY_REQUEST_TYPE => request_type,
              Ext::HEADER_CLIENT_LIBRARY_LANGUAGE => Core::Environment::Ext::LANG,
              Ext::HEADER_CLIENT_LIBRARY_VERSION => DDTrace::VERSION::STRING,

              # Enable debug mode for telemetry
              # HEADER_TELEMETRY_DEBUG_ENABLED => 'true',
            }
          end

          def adapter
            @adapter ||= Http::Adapters::Net.new(hostname: @host, port: @port, ssl: @ssl)
          end
        end
      end
    end
  end
end
