# frozen_string_literal: true

require_relative '../../../../tracing'
require_relative '../../../metadata/ext'
require_relative '../../analytics'
require_relative '../ext'
require_relative '../event'

module Datadog
  module Tracing
    module Contrib
      module ActionView
        module Events
          # Defines instrumentation for render_partial.action_view event
          module RenderPartial
            include ActionView::Event

            EVENT_NAME = 'render_partial.action_view'

            module_function

            def event_name
              self::EVENT_NAME
            end

            def span_name
              Ext::SPAN_RENDER_PARTIAL
            end

            def span_options
              span_options = {}

              span_options[:service] = configuration[:service_name] if configuration[:service_name]
              span_options[:type] = Tracing::Metadata::Ext::HTTP::TYPE_TEMPLATE

              span_options[:tags] = {
                Tracing::Metadata::Ext::TAG_COMPONENT => Ext::TAG_COMPONENT,
                Tracing::Metadata::Ext::TAG_OPERATION => Ext::TAG_OPERATION_RENDER_PARTIAL,
              }

              Contrib::Analytics.measured_span_option(span_options)

              span_options
            end

            def process(span, _event, _id, payload)
              if (template_name = Utils.normalize_template_name(payload[:identifier]))
                span.resource = template_name
                span.set_tag(Ext::TAG_TEMPLATE_NAME, template_name)
              end

              record_exception(span, payload)
            rescue StandardError => e
              Datadog.logger.debug(e.message)
            end
          end
        end
      end
    end
  end
end
