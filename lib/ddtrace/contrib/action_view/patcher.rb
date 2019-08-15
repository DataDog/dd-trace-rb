require 'ddtrace/ext/http'
require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/action_view/ext'
require 'ddtrace/contrib/action_view/instrumentation'
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
            if defined?(::ActionView::TemplateRenderer) && defined?(::ActionView::PartialRenderer)
              ::ActionView::TemplateRenderer.send(:prepend, Instrumentation::TemplateRenderer::Rails31Plus)
              ::ActionView::PartialRenderer.send(:prepend, Instrumentation::PartialRenderer)
            elsif defined?(::ActionView::Rendering) && defined?(::ActionView::Partials::PartialRenderer)
              # NOTE: Rails < 3.1 compatibility: different classes are used
              ::ActionView::Rendering.send(:prepend, Instrumentation::TemplateRenderer::Rails30)
              ::ActionView::Partials::PartialRenderer.send(:prepend, Instrumentation::PartialRenderer)
            else
              Datadog::Tracer.log.debug('Expected Template/Partial classes not found; template rendering disabled')
            end
          end
        end
      end
    end
  end
end
