require_relative '../../../datadog/core/encoding'

require_relative 'api/map'
require_relative 'api/spec'

require_relative 'traces'

module Datadog
  module Transport
    module HTTP
      # Namespace for API components
      module API
        # Default API versions
        V4 = 'v0.4'.freeze
        V3 = 'v0.3'.freeze

        module_function

        def defaults
          Map[
            V4 => Spec.new do |s|
              s.traces = Traces::API::Endpoint.new(
                '/v0.4/traces'.freeze,
                Core::Encoding::MsgpackEncoder,
                service_rates: true
              )
            end,
            V3 => Spec.new do |s|
              s.traces = Traces::API::Endpoint.new(
                '/v0.3/traces'.freeze,
                Core::Encoding::MsgpackEncoder
              )
            end,
          ].with_fallbacks(V4 => V3)
        end
      end
    end
  end
end
