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

        def patched?
          done?(:active_model_serializers)
        end

        def patch
          do_once(:active_model_serializers) do
            begin
              # Subscribe to ActiveModelSerializers events
              Events.subscribe!
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply ActiveModelSerializers integration: #{e}")
            end
          end
        end

        def get_option(option)
          Datadog.configuration[:active_model_serializers].get_option(option)
        end
      end
    end
  end
end
