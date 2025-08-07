# frozen_string_literal: true

require_relative '../../../utils/hash_coercion'
require_relative '../../../instrumentation/gateway/argument'

module Datadog
  module AppSec
    module Contrib
      module Rails
        module Patches
          # A patch targeting `AbstractController::Rendering#render_to_body`
          # method to capture JSON response body right before it is serialized.
          module RenderToBodyPatch
            def render_to_body(options = {})
              return super unless options.key?(:json)

              context = request.env[Datadog::AppSec::Ext::CONTEXT_KEY]
              return super unless context

              data = Utils::HashCoercion.coerce(options[:json])
              return super unless data

              container = Instrumentation::Gateway::DataContainer.new(data, context: context)
              Instrumentation.gateway.push('rails.response.body.json', container)

              super
            end
          end
        end
      end
    end
  end
end
