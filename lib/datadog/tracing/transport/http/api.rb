# frozen_string_literal: true

require_relative '../../../core/encoding'

require_relative '../../../core/transport/http/api/map'
require_relative '../../../core/transport/http/api/instance'
require_relative '../../../core/transport/http/api/spec'

require_relative 'traces'

module Datadog
  module Tracing
    module Transport
      module HTTP
        # Namespace for API components
        module API
          # Default API versions
          V4 = 'v0.4'
          V3 = 'v0.3'

          module_function

          def defaults
            Core::Transport::HTTP::API::Map[
              V4 => Spec.new do |s|
                s.traces = Traces::API::Endpoint.new(
                  '/v0.4/traces',
                  Core::Encoding::MsgpackEncoder,
                  service_rates: true
                )
              end,
              V3 => Spec.new do |s|
                s.traces = Traces::API::Endpoint.new(
                  '/v0.3/traces',
                  Core::Encoding::MsgpackEncoder
                )
              end,
            ].with_fallbacks(V4 => V3)
          end

          class Instance < Core::Transport::HTTP::API::Instance
            include Traces::API::Instance
          end

          class Spec < Core::Transport::HTTP::API::Spec
            include Traces::API::Spec
          end
        end
      end
    end
  end
end
