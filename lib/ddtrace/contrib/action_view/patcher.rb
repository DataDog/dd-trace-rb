require 'ddtrace/ext/http'
require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/action_view/events'
require 'ddtrace/contrib/action_view/ext'
require 'ddtrace/contrib/action_view/instrumentation/partial_renderer'
require 'ddtrace/contrib/action_view/instrumentation/template_renderer'
require 'ddtrace/contrib/action_view/utils'

module Datadog
  module Contrib
    module ActionView
      # Patcher enables patching of ActionView module.
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
              Datadog::Tracer.log.error("Unable to apply Action View integration: #{e} Location: #{e.backtrace.first}")
            end
          end
        end

        def patch_renderer
          do_once(:patch_renderer) do
            if Integration.version >= Gem::Version.new('4.0.0')
              Events.subscribe!
            elsif defined?(::ActionView::TemplateRenderer) && defined?(::ActionView::PartialRenderer)
              # Rails < 4 compatibility:
              #  Rendering events are not nested in this version, creating
              #  render_partial spans outside of the parent render_template span.
              #  We fall back to manual patching instead.
              ::ActionView::TemplateRenderer.send(:prepend, Instrumentation::TemplateRenderer::RailsLessThan4)
              ::ActionView::PartialRenderer.send(:prepend, Instrumentation::PartialRenderer::RailsLessThan4)
            elsif defined?(::ActionView::Rendering) && defined?(::ActionView::Partials::PartialRenderer)
              # NOTE: Rails < 3.1 compatibility: different classes are used
              ::ActionView::Rendering.send(:prepend, Instrumentation::TemplateRenderer::Rails30)
              ::ActionView::Partials::PartialRenderer.send(:prepend, Instrumentation::PartialRenderer::RailsLessThan4)
            else
              Datadog::Tracer.log.debug('Expected Template/Partial classes not found; template rendering disabled')
            end
          end
        end
      end
    end
  end
end
