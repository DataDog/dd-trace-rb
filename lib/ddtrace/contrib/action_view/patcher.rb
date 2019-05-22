require 'ddtrace/ext/http'
require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/action_view/ext'
require 'ddtrace/contrib/action_view/instrumentation'
require 'ddtrace/contrib/action_view/utils'

module Datadog
  module Contrib
    module ActionView
      # Patcher enables patching of ActionView module.
      # rubocop:disable Metrics/ModuleLength
      # rubocop:disable Metrics/MethodLength
      module Patcher
        include Contrib::Patcher

        module_function

        def patched?
          done?(:action_view)
        end

        def patch
          do_once(:action_view) do
            begin
              patch_renderer
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply Action View integration: #{e}")
            end
          end
        end

        def patch_renderer
          do_once(:patch_renderer) do
            if defined?(::ActionView::TemplateRenderer) && defined?(::ActionView::PartialRenderer)
              patch_template_renderer(::ActionView::TemplateRenderer)
              patch_partial_renderer(::ActionView::PartialRenderer)
            elsif defined?(::ActionView::Rendering) && defined?(::ActionView::Partials::PartialRenderer)
              # NOTE: Rails < 3.1 compatibility: different classes are used
              patch_template_renderer(::ActionView::Rendering)
              patch_partial_renderer(::ActionView::Partials::PartialRenderer)
            else
              Datadog::Tracer.log.debug('Expected Template/Partial classes not found; template rendering disabled')
            end
          end
        end

        def patch_template_renderer(klass)
          # rubocop:disable Metrics/BlockLength
          do_once(:patch_template_renderer) do
            klass.class_eval do
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
                  # arguments based on render_template signature (stable since Rails 3.2)
                  template = args[0]
                  layout_name = args[1]

                  # update the tracing context with computed values before the rendering
                  template_name = template.try('identifier')
                  template_name = Utils.normalize_template_name(template_name)
                  layout = if layout_name.is_a?(String)
                             # NOTE: Rails < 3.1 compatibility: the second argument is the layout name
                             layout_name
                           else
                             layout_name.try(:[], 'virtual_path')
                           end
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

              if klass.private_method_defined?(:render_template) || klass.method_defined?(:render_template)
                alias_method :render_template_without_datadog, :render_template
                alias_method :render_template, :render_template_with_datadog
              else
                # NOTE: Rails < 3.1 compatibility: the method name is different
                alias_method :render_template_without_datadog, :_render_template
                alias_method :_render_template, :render_template_with_datadog
              end
            end
          end
        end

        def patch_partial_renderer(klass)
          do_once(:patch_partial_renderer) do
            klass.class_eval do
              def render_with_datadog(*args, &block)
                datadog_tracer.trace(
                  Ext::SPAN_RENDER_PARTIAL,
                  span_type: Datadog::Ext::HTTP::TEMPLATE
                ) do |span|
                  with_datadog_span(span) { render_without_datadog(*args) }
                end
              end

              def render_partial_with_datadog(*args)
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
                render_partial_without_datadog(*args)
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
              alias_method :render_partial_without_datadog, :render_partial
              alias_method :render_partial, :render_partial_with_datadog
            end
          end
        end
      end
    end
  end
end
