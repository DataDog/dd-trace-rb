require 'ddtrace/encoding'

require 'ddtrace/transport/http/api/map'
require 'ddtrace/transport/http/api/routes'
require 'ddtrace/transport/http/api/endpoints'

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
            V4 => Routes[
              traces: [
                '/v0.4/traces',
                TraceEndpoint.new(Encoding::MsgpackEncoder)
              ]
            ],
            V3 => Routes[
              traces: [
                '/v0.3/traces',
                TraceEndpoint.new(Encoding::MsgpackEncoder)
              ]
            ],
            V2 => Routes[
              traces: [
                '/v0.2/traces',
                TraceEndpoint.new(Encoding::JSONEncoder)
              ]
            ]
          ].with_fallbacks(V4 => V3, V3 => V2)
        end
      end
    end
  end
end
