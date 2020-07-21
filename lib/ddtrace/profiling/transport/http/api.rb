require 'ddtrace/transport/http/api/map'
require 'ddtrace/profiling/encoding/profile'
require 'ddtrace/profiling/transport/http/api/spec'
require 'ddtrace/profiling/transport/http/api/instance'
require 'ddtrace/profiling/transport/http/api/endpoint'

module Datadog
  module Profiling
    module Transport
      module HTTP
        # Extensions for HTTP API Spec
        module API
          # Default API versions
          V1 = 'v1'.freeze

          module_function

          def agent_defaults
            @agent_defaults ||= Datadog::Transport::HTTP::API::Map[
              V1 => Spec.new do |s|
                s.profiles = Endpoint.new(
                  '/profiling/v1/input'.freeze,
                  Profiling::Encoding::Profile::Protobuf
                )
              end
            ]
          end

          def api_defaults
            @api_defaults ||= Datadog::Transport::HTTP::API::Map[
              V1 => Spec.new do |s|
                s.profiles = Endpoint.new(
                  '/v1/input'.freeze,
                  Profiling::Encoding::Profile::Protobuf
                )
              end
            ]
          end
        end
      end
    end
  end
end
