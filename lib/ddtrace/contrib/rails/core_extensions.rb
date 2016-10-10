module Datadog
  # some stuff
  module RendererExtension
    def render_template(*args)
      ActiveSupport::Notifications.instrument 'start_render_template.action_view'
      super(*args)
    end
  end

  # some stuff
  module PartialRendererExtension
    def render_partial(*args)
      ActiveSupport::Notifications.instrument 'start_render_partial.action_view'
      super(*args)
    end
  end
end

module ActionView
  # some stuff
  class Renderer
    prepend Datadog::RendererExtension
  end

  # some stuff
  class PartialRenderer
    prepend Datadog::PartialRendererExtension
  end
end
