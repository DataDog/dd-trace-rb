# frozen_string_literal: true

require_relative '../../../../tracing'
require_relative '../../../metadata/ext'
require_relative '../../analytics'
require_relative '../ext'
require_relative '../event'

module Datadog
  module Tracing
    module Contrib
      module ViewComponent
        module Events
          # Defines instrumentation for render.view_component event
          module Render
            include ViewComponent::Event

            EVENT_NAME = 'render.view_component'
            DEPRECATED_EVENT_NAME = '!render.view_component'

            module_function

            def event_name
              return DEPRECATED_EVENT_NAME if configuration[:use_deprecated_instrumentation_name]
              EVENT_NAME
            end

            def span_name
              Ext::SPAN_RENDER
            end

            def on_start(span, _event, _id, payload)
              span.service = configuration[:service_name] if configuration[:service_name]
              span.type = Tracing::Metadata::Ext::HTTP::TYPE_TEMPLATE

              span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT)
              span.set_tag(Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION_RENDER)

              span.resource = payload[:name]
              span.set_tag(Ext::TAG_COMPONENT_NAME, payload[:name])

              if (identifier = Utils.normalize_component_identifier(payload[:identifier]))
                span.set_tag(Ext::TAG_COMPONENT_IDENTIFIER, identifier)
              end

              # Measure service stats
              Contrib::Analytics.set_measured(span)
            end
          end
        end
      end
    end
  end
end
