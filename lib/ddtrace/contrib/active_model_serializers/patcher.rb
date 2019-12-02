require 'ddtrace/contrib/patcher'
require 'ddtrace/ext/app_types'
require 'ddtrace/contrib/active_model_serializers/ext'
require 'ddtrace/contrib/active_model_serializers/events'

module Datadog
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
