require 'ddtrace/contrib/action_view/ext'

module Datadog
  module Contrib
    module ActionView
      # Defines instrumentation for ActionView
      module Instrumentation
        # Instrumentation for template rendering
        module TemplateRenderer
          # Rails < 3.1 template rendering
          module Rails30
            # rubocop:disable Metrics/MethodLength
            def self.prepended(base)
              # rubocop:disable Metrics/BlockLength
              base.class_eval do
                def render_with_datadog(*args, &block)
                  # NOTE: This check exists purely for Rails 3.0 compatibility.
                  #       The 'if' part can be removed when support for Rails 3.0 is removed.
                  if active_datadog_span
                    render_without_datadog(*args, &block)
                  else
                    datadog_tracer.trace(
                      Ext::SPAN_RENDER_TEMPLATE,
                      span_type: Datadog::Ext::HTTP::TEMPLATE
                    ) do |span|
                      with_datadog_span(span) { render_without_datadog(*args, &block) }
                    end
                  end
                end

                def render_template_with_datadog(*args)
                  begin
                    template = args[0]
                    layout_name = args[1]

                    # update the tracing context with computed values before the rendering
                    template_name = template.try('identifier')
                    template_name = Utils.normalize_template_name(template_name)

                    if template_name
                      active_datadog_span.set_tag(
                        Ext::TAG_TEMPLATE_NAME,
                        template_name
                      )
                    end

                    if layout_name
                      active_datadog_span.set_tag(
                        Ext::TAG_LAYOUT,
                        layout_name
                      )
                    end
                  rescue StandardError => e
                    Datadog::Tracer.log.debug(e.message)
                  end

                  # execute the original function anyway
                  render_template_without_datadog(*args)
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

                # method aliasing to patch the class
                alias_method :render_without_datadog, :render
                alias_method :render, :render_with_datadog

                alias_method :render_template_without_datadog, :_render_template
                alias_method :_render_template, :render_template_with_datadog
              end
            end
          end

          # Rails >= 3.1 template rendering
          module Rails31Plus
            def render(*args, &block)
              datadog_tracer.trace(
                Ext::SPAN_RENDER_TEMPLATE,
                span_type: Datadog::Ext::HTTP::TEMPLATE
              ) do |span|
                with_datadog_span(span) { super(*args, &block) }
              end
            end

            def render_template(*args)
              begin
                # arguments based on render_template signature (stable since Rails 3.2)
                template = args[0]
                layout_name = args[1]

                # update the tracing context with computed values before the rendering
                template_name = template.try('identifier')
                template_name = Utils.normalize_template_name(template_name)
                layout = layout_name.try(:[], 'virtual_path')

                if template_name
                  active_datadog_span.set_tag(
                    Ext::TAG_TEMPLATE_NAME,
                    template_name
                  )
                end

                if layout
                  active_datadog_span.set_tag(
                    Ext::TAG_LAYOUT,
                    layout
                  )
                end
              rescue StandardError => e
                Datadog::Tracer.log.debug(e.message)
              end

              # execute the original function anyway
              super(*args)
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
          end
        end

        # Instrumentation for partial rendering
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
              template_name = Utils.normalize_template_name(@template.try('identifier'))
              if template_name
                active_datadog_span.set_tag(
                  Ext::TAG_TEMPLATE_NAME,
                  template_name
                )
              end
            rescue StandardError => e
              Datadog::Tracer.log.debug(e.message)
            end

            # execute the original function anyway
            super(*args)
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
        end
      end
    end
  end
end
