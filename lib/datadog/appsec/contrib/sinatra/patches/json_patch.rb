# frozen_string_literal: true

require_relative '../../../utils/hash_coercion'
require_relative '../../../instrumentation/gateway/argument'

module Datadog
  module AppSec
    module Contrib
      module Sinatra
        module Patches
          # A patch targeting `Sinatra::JSON#json` method to capture JSON response
          # body right before it is serialized.
          module JsonPatch
            def json(object, options = {})
              context = @request.env[Datadog::AppSec::Ext::CONTEXT_KEY]
              return super unless context

              data = Utils::HashCoercion.coerce(object)
              return super unless data

              container = Instrumentation::Gateway::DataContainer.new(data, context: context)
              Instrumentation.gateway.push('sinatra.response.body.json', container)

              super
            end
          end
        end
      end
    end
  end
end
