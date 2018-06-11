require 'ddtrace/contrib/rails/utils'

module Datadog
  module Contrib
    module Rails
      # Code used to create and handle 'rails.render_template' and 'rails.render_partial' spans.
      module ActionView
        include Datadog::Patcher

        def self.instrument
          # patch Rails core components
          do_once(:instrument) do
            Datadog::RailsRendererPatcher.patch_renderer
          end
        end
      end
    end
  end
end
