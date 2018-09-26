require 'ddtrace/contrib/active_model_serializers/ext'
require 'ddtrace/contrib/active_model_serializers/event'

module Datadog
  module Contrib
    module ActiveModelSerializers
      module Events
        # Defines instrumentation for !serialize.active_model_serializers event
        module Serialize
          include ActiveModelSerializers::Event

          EVENT_NAME = '!serialize.active_model_serializers'.freeze

          module_function

          def supported?
            Gem.loaded_specs['active_model_serializers'] \
              && ( \
                Gem.loaded_specs['active_model_serializers'].version >= Gem::Version.new('0.9') \
                && Gem.loaded_specs['active_model_serializers'].version < Gem::Version.new('0.10') \
              )
          end

          def event_name
            self::EVENT_NAME
          end

          def span_name
            Ext::SPAN_SERIALIZE
          end
        end
      end
    end
  end
end
