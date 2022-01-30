# typed: false
require 'datadog/tracing/metadata/ext'
require 'ddtrace/contrib/active_model_serializers/ext'
require 'ddtrace/contrib/active_model_serializers/event'

module Datadog
  module Tracing
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

            def process(span, _event, _id, payload)
              span.set_tag(Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION_RENDER)

              set_common_tags(span, payload)
            rescue StandardError => e
              Datadog.logger.debug(e.message)
            end
          end
        end
      end
    end
  end
end
