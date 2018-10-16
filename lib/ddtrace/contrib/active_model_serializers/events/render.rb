require 'ddtrace/contrib/active_model_serializers/ext'
require 'ddtrace/contrib/active_model_serializers/event'

module Datadog
  module Contrib
    module ActiveModelSerializers
      module Events
        # Defines instrumentation for render.active_model_serializers event
        module Render
          include ActiveModelSerializers::Event

          EVENT_NAME = 'render.active_model_serializers'.freeze

          module_function

          def supported?
            Gem.loaded_specs['active_model_serializers'] \
              && Gem.loaded_specs['active_model_serializers'].version >= Gem::Version.new('0.10')
          end

          def event_name
            self::EVENT_NAME
          end

          def span_name
            Ext::SPAN_RENDER
          end
        end
      end
    end
  end
end
