require 'ddtrace/encoding'

require 'ddtrace/transport/http/api/map'
require 'ddtrace/transport/http/api/spec'

require 'ddtrace/transport/http/traces'

module Datadog
  module Transport
    module HTTP
      # Namespace for API components
      module API
        # Default API versions
        V4 = 'v0.4'.freeze
        V3 = 'v0.3'.freeze
        V2 = 'v0.2'.freeze

        module_function

        def defaults
          Map[
            V4 => Spec.new do |s|
              s.traces = Traces::API::Endpoint.new(
                '/v0.4/traces'.freeze,
                Encoding::MsgpackEncoder,
                service_rates: true
              )
            end,
            V3 => Spec.new do |s|
              s.traces = Traces::API::Endpoint.new(
                '/v0.3/traces'.freeze,
                Encoding::MsgpackEncoder
              )
            end,
            V2 => Spec.new do |s|
              s.traces = Traces::API::Endpoint.new(
                '/v0.2/traces'.freeze,
                Encoding::JSONEncoder
              )
            end
          ].with_fallbacks(V4 => V3, V3 => V2)
        end
      end
    end
  end
end
