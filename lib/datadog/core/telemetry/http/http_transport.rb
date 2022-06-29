# typed: true

require 'datadog/core/configuration/settings'
require 'datadog/core/telemetry/http/env'
require 'datadog/core/telemetry/http/ext'
require 'datadog/core/telemetry/http/adapters/net'

module Datadog
  module Core
    module Telemetry
      module Http
        # Class to send telemetry data to Telemetry API
        class Transport
          def initialize(agent_settings: nil)
            set_url
          end

          def request(request_type:, payload:)
            env = Http::Env.new
            adapter = Http::Adapters::Net.new(hostname: @host, port: @port, ssl: @ssl)
            env.path = @path
            env.body = payload
            env.headers = headers(request_type: request_type)
            adapter.post(env)
          end

          private

          def headers(request_type:, api_version: Http::Ext::API_VERSION)
            {
              Http::Ext::HEADER_CONTENT_TYPE => Http::Ext::CONTENT_TYPE_APPLICATION_JSON,
              Http::Ext::HEADER_DD_TELEMETRY_API_VERSION => api_version,
              Http::Ext::HEADER_DD_TELEMETRY_REQUEST_TYPE => request_type,
            }.tap do |headers|
              headers[Http::Ext::HEADER_DD_API_KEY] = Datadog.configuration.api_key if agentless?
            end
          end

          def agentless?
            true
          end

          def set_url
            if agentless?
              # @host = Http::Ext::AGENTLESS_HOST
              @host = 'all-http-intake.logs.datad0g.com'
              @port = 443
              @ssl = true
              @path = Http::Ext::AGENTLESS_ENDPOINT
            else
              agent_configuration = Datadog.configuration.agent
              @host = agent_configuration.host
              @port = agent_configuration.port
              @ssl = false
              @path = Http::Ext::AGENT_ENDPOINT
            end
          end
        end
      end
    end
  end
end
