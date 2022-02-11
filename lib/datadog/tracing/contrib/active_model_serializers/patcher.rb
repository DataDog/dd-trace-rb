# typed: true
require 'datadog/tracing'
require 'datadog/tracing/contrib/patcher'
require 'datadog/tracing/contrib/active_model_serializers/ext'
require 'datadog/tracing/contrib/active_model_serializers/events'

module Datadog
  module Tracing
    module Contrib
      module ActiveModelSerializers
        # Patcher enables patching of 'active_model_serializers' module.
        module Patcher
          include Contrib::Patcher

          module_function

          def target_version
            Integration.version
          end

          def patch
            Events.subscribe!
          end

          def get_option(option)
            Datadog.configuration[:active_model_serializers].get_option(option)
          end
        end
      end
    end
  end
end
