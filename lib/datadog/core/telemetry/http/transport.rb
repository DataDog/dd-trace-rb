# frozen_string_literal: true

require_relative '../../configuration/settings'
require_relative '../../environment/ext'
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
          def self.build_agent_transport(agent_settings)
            Transport.new(
              host: agent_settings.hostname,
              port: agent_settings.port,
              path: Http::Ext::AGENT_ENDPOINT
            )
          end

          def self.build_agentless_transport(api_key:, dd_site:, url_override: nil)
            url = url_override || "https://#{Http::Ext::AGENTLESS_HOST_PREFIX}.#{dd_site}:443"

            uri = URI.parse(url)
            raise "Invalid agentless mode URL: #{url}" if uri.host.nil?

            Transport.new(
              host: uri.host,
              port: uri.port || 80,
              path: Http::Ext::AGENTLESS_ENDPOINT,
              ssl: uri.scheme == 'https' || uri.port == 443,
              api_key: api_key
            )
          end

          attr_reader \
            :host,
            :port,
            :ssl,
            :path,
            :api_key

          def initialize(host:, port:, path:, ssl: false, api_key: nil)
            @host = host
            @port = port
            @ssl = ssl
            @path = path
            @api_key = api_key
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
            result = {
              Core::Transport::Ext::HTTP::HEADER_DD_INTERNAL_UNTRACED_REQUEST => '1',
              Ext::HEADER_CONTENT_TYPE => Http::Ext::CONTENT_TYPE_APPLICATION_JSON,
              Ext::HEADER_DD_TELEMETRY_API_VERSION => api_version,
              Ext::HEADER_DD_TELEMETRY_REQUEST_TYPE => request_type,
              Ext::HEADER_CLIENT_LIBRARY_LANGUAGE => Core::Environment::Ext::LANG,
              Ext::HEADER_CLIENT_LIBRARY_VERSION => Core::Environment::Identity.gem_datadog_version_semver2,

              # Enable debug mode for telemetry
              # HEADER_TELEMETRY_DEBUG_ENABLED => 'true',
            }

            result[Ext::HEADER_DD_API_KEY] = api_key unless api_key.nil?

            result
          end

          def adapter
            @adapter ||= Http::Adapters::Net.new(hostname: @host, port: @port, ssl: @ssl)
          end
        end
      end
    end
  end
end
