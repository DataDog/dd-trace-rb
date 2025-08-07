# frozen_string_literal: true

require_relative '../../../utils/hash_serializer'
require_relative '../../../instrumentation/gateway/argument'

module Datadog
  module AppSec
    module Contrib
      module Sinatra
        module Patches
          # TODO Write description for the patch
          module JsonHelperPatch
            def json(object, options = {})
              context = @request.env[Datadog::AppSec::Ext::CONTEXT_KEY]
              return super unless context

              # FIXME: Rename method and maybe module
              data = Utils::HashSerializer.to_hash(object)
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
