# frozen_string_literal: true

require_relative 'endpoint'
require_relative 'ext'
require_relative 'instrumentation'
require_relative '../patcher'

module Datadog
  module Tracing
    module Contrib
      module Grape
        # Patcher enables patching of 'grape' module.
        module Patcher
          include Contrib::Patcher

          module_function

          def target_version
            Integration.version
          end

          def patch
            # Patch endpoints
            ::Grape::Endpoint.prepend(Instrumentation::InstanceMethods)
            if target_version < Gem::Version.new('3.0.0')
              ::Grape::Endpoint.singleton_class.prepend(Instrumentation::GenerateApiMethodPatch)
            else
              ::Grape::Endpoint.prepend(Instrumentation::ExecutePatch)
            end

            # Subscribe to ActiveSupport events
            Endpoint.subscribe
          end
        end
      end
    end
  end
end
