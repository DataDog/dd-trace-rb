# some stuff
module RendererExtension
  def render_template(*args)
    ActiveSupport::Notifications.instrument 'start_render_template.action_view', this: :data
    super(*args)
  end
end

# some stuff
module PartialRendererExtension
  def render_partial(*args)
    ActiveSupport::Notifications.instrument 'start_render_partial.action_view', this: :data
    super(*args)
  end
end

module ActionView
  # some stuff
  class Renderer
    prepend RendererExtension
  end

  # some stuff
  class PartialRenderer
    prepend PartialRendererExtension
  end
end
