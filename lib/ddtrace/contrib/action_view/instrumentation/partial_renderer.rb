require 'ddtrace/contrib/action_view/ext'

module Datadog
  module Contrib
    module ActionView
      module Instrumentation
        # Legacy instrumentation for partial rendering for Rails < 4
        module PartialRenderer
          def render(*args, &block)
            datadog_tracer.trace(
              Ext::SPAN_RENDER_PARTIAL,
              span_type: Datadog::Ext::HTTP::TEMPLATE
            ) do |span|
              with_datadog_span(span) { super(*args) }
            end
          end

          def render_partial(*args)
            begin
              template = datadog_template(*args)

              datadog_render_partial(template)
            rescue StandardError => e
              Datadog::Logger.log.debug(e.message)
            end

            # execute the original function anyway
            super(*args)
          end

          def datadog_render_partial(template)
            template_name = Utils.normalize_template_name(template.try('identifier'))

            if template_name
              active_datadog_span.resource = template_name
              active_datadog_span.set_tag(
                Ext::TAG_TEMPLATE_NAME,
                template_name
              )
            end
          end

          private

          attr_accessor :active_datadog_span

          def datadog_tracer
            Datadog.configuration[:action_view][:tracer]
          end

          def with_datadog_span(span)
            self.active_datadog_span = span
            yield
          ensure
            self.active_datadog_span = nil
          end

          # Rails < 4 partial rendering
          # ActiveSupport events are used instead for Rails >= 4
          module RailsLessThan4
            include PartialRenderer

            def datadog_template(*args)
              @template
            end
          end
        end
      end
    end
  end
end
