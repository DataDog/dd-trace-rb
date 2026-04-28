# frozen_string_literal: true

::Hanami.plugin do
  Datadog.configure do |c|
    c.tracing.instrument :rack
  end

  if Datadog.configuration.tracing[:rack][:use_events] &&
      Datadog::Tracing::Contrib::Rack::Integration.version >= Datadog::Tracing::Contrib::Rack::Integration::MINIMUM_EVENTS_VERSION
    require 'datadog/tracing/contrib/rack/event_handler'
    middleware.use ::Rack::Events, [Datadog::Tracing::Contrib::Rack::EventHandler.new]
  else
    middleware.use Datadog::Tracing::Contrib::Rack::TraceMiddleware
  end
end

::Hanami::Application.singleton_class.prepend(
  Module.new do
    def inherited(base)
      super

      base.configure do
        controller.prepare do
          use Datadog::Tracing::Contrib::Hanami::ActionTracer, self
        end
      end
    end
  end
)
