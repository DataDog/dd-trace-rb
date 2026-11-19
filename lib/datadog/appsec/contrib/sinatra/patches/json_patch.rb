# frozen_string_literal: true

require_relative "../../../instrumentation/gateway/argument"

module Datadog
  module AppSec
    module Contrib
      module Sinatra
        module Patches
          # A patch for `Sinatra::JSON#json` that captures the serialized
          # response body for AppSec inspection
          module JsonPatch
            def json(object, options = {})
              context = @request.env[Datadog::AppSec::Ext::CONTEXT_KEY] # : Context?
              return super unless context

              # NOTE: Custom renderers can return streaming bodies, which we
              #       currently do not inspect
              body = super
              return body unless body.is_a?(String)

              container = Instrumentation::Gateway::DataContainer.new(body, context: context)
              Instrumentation.gateway.push("sinatra.response.body.json", container)

              body
            end
          end
        end
      end
    end
  end
end
