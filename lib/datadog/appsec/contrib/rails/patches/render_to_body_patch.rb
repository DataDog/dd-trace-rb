# frozen_string_literal: true

require_relative "../../../instrumentation/gateway/argument"

module Datadog
  module AppSec
    module Contrib
      module Rails
        module Patches
          # A patch for `AbstractController::Rendering#render_to_body` that captures
          # the serialized JSON response body for AppSec inspection
          module RenderToBodyPatch
            def render_to_body(options = {})
              return super unless options.key?(:json)

              context = request.env[Datadog::AppSec::Ext::CONTEXT_KEY]
              return super unless context

              # NOTE: Custom renderers can return streaming bodies, which we
              #       currently do not inspect
              body = super
              return body unless body.is_a?(String)

              container = Instrumentation::Gateway::DataContainer.new(body, context: context)
              Instrumentation.gateway.push("rails.response.body.json", container)

              body
            end
          end
        end
      end
    end
  end
end
