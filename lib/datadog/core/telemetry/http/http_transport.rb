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
          def initialize(host:, port: nil, path: nil)
            @host = host
            @port = port
            @path = path
          end

          def request(request_type:, payload:)
            env = Http::Env.new
            adapter = Http::Adapters::Net.new(hostname: @host, port: @port)
            env.path = @path
            env.body = payload(payload)
            env.headers = headers(request_type: request_type, content_length: content_length(payload))
            adapter.post(env)
          end

          def headers(request_type:, content_length:, api_version: Http::Ext::API_VERSION)
            headers = {
              Http::Ext::HEADER_DD_API_KEY => Datadog.configuration.api_key,
              Http::Ext::HEADER_CONTENT_TYPE => Http::Ext::CONTENT_TYPE_APPLICATION_JSON,
              # Http::Ext::HEADER_CONTENT_LENGTH => content_length,
              Http::Ext::HEADER_DD_TELEMETRY_API_VERSION => api_version,
              Http::Ext::HEADER_DD_TELEMETRY_REQUEST_TYPE => request_type,
            }
          end

          def payload(req)
            flatten_request(req).to_json
          end

          def content_length(req)
            req.to_json.length
          end

          def flatten_request(req)
            hash = {}
            req.instance_variables.each do |k|
              v = req.instance_variable_get(k.to_s)
              if v.is_a?(Array)
                arr_obj = []
                v.each do |obj|
                  arr_obj << flatten_request(obj) unless obj.instance_variables.empty?
                end
                hash[k.to_s[1..-1]] = arr_obj
              elsif !v.instance_variables.empty?
                hash[k.to_s[1..-1]] = flatten_request(v)
              else
                hash[k.to_s[1..-1]] = v
              end
            end
            hash["debug"] = true
            hash
          end
        end
      end
    end
  end
end
