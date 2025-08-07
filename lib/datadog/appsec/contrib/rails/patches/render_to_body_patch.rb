# frozen_string_literal: true

require_relative '../../../utils/hash_serializer'
require_relative '../../../instrumentation/gateway/argument'

module Datadog
  module AppSec
    module Contrib
      module Rails
        module Patches
          # TODO Write description for the patch
          module RenderToBodyPatch
            def render_to_body(options = {})
              return super unless options.key?(:json)

              context = request.env[Datadog::AppSec::Ext::CONTEXT_KEY]
              return super unless context

              data = Utils::HashSerializer.to_hash(options[:json])
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
