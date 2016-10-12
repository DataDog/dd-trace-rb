module Datadog
  # TODO[manu]: write docs
  module RendererExtension
    def render_template(*args)
      ActiveSupport::Notifications.instrument 'start_render_template.action_view'
      super(*args)
    end
  end

  # TODO[manu]: write docs
  module PartialRendererExtension
    def render_partial(*args)
      ActiveSupport::Notifications.instrument 'start_render_partial.action_view'
      super(*args)
    end
  end
end

module ActionView
  # TODO[manu]: write docs
  class Renderer
    prepend Datadog::RendererExtension
  end

  # TODO[manu]: write docs
  class PartialRenderer
    prepend Datadog::PartialRendererExtension
  end
end
