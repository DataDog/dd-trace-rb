module Datadog
  module Core
    module Telemetry
      module Http
        module Ext
          HEADER_DD_API_KEY = 'DD-API-KEY'.freeze
          HEADER_CONTENT_TYPE = 'Content-Type'.freeze
          HEADER_CONTENT_LENGTH = 'Content-Length'.freeze
          HEADER_DD_TELEMETRY_API_VERSION = 'DD-Telemetry-API-Version'.freeze
          HEADER_DD_TELEMETRY_REQUEST_TYPE = 'DD-Telemetry-Request-Type'.freeze

          CONTENT_TYPE_APPLICATION_JSON = 'application/json'.freeze
          API_VERSION = 'v1'.freeze

          AGENT_ENDPOINT = '/telemetry/proxy/api/v2/apmtelemetry'.freeze
        end
      end
    end
  end
end
