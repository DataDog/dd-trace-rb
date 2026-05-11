# frozen_string_literal: true

module Datadog
  module AppSec
    module Contrib
      module Rack
        module ResponseBody
          # NOTE: We compute content length only for fixed-size response bodies,
          #       ignoring streaming bodies to avoid buffering.
          #
          #       On Rack 3.x, `body.to_ary` on a BodyProxy triggers `close` on all
          #       nested BodyProxy layers. This is safe because web servers, like Puma
          #       handles already-closed bodies (its own `to_ary` becomes a no-op).
          #
          # @see Puma::Response#prepare_response
          # @see https://github.com/puma/puma/blob/b1271222cbf21868f3fb64154caa4d03936a7b9e/lib/puma/response.rb#L165-L168
          def self.content_length(body)
            return unless body.respond_to?(:to_ary)

            # NOTE: When `to_ary` exists but returns `nil`, the body will be
            #       transferred in chunks and we can't compute content length
            #       without buffering it.
            body_ary = body.to_ary
            return unless body_ary.is_a?(Array)

            body_ary.sum { |part| part.is_a?(String) ? part.bytesize : 0 }
          rescue => e
            AppSec.telemetry.report(e, description: 'AppSec: Failed to compute body content length')

            nil
          end
        end
      end
    end
  end
end
