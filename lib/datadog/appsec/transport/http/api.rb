# typed: ignore

require_relative '../../../core/encoding'

require_relative '../../../../ddtrace/transport/http/api/map'
# TODO: because of include in http/negotiation
#require_relative '../../../../ddtrace/transport/http/api/spec'
require_relative 'api/spec'

require_relative 'negotiation'

module Datadog
  module AppSec
    module Transport
      module HTTP
        # Namespace for API components
        module API
          # Default API versions
          TOP = ''.freeze
          V7 = 'v0.7'.freeze

          module_function

          def defaults
            Datadog::Transport::HTTP::API::Map[
              TOP => Spec.new do |s|
                s.info = Negotiation::API::Endpoint.new(
                  '/info'.freeze,
                )
              end,
              #V7 => Spec.new do |s|
              #  s.config = Config::API::Endpoint.new(
              #    '/v0.7/config'.freeze,
              #    Core::Encoding::MsgpackEncoder,
              #    service_rates: true
              #  )
              #end,
            ]
          end
        end
      end
    end
  end
end
