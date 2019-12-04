module Datadog
  module Contrib
    module Resque
      module Enqueue
        def enqueue_to(queue_name, klass, *args)
          pin = Datadog::Pin.get_from(::Resque)
          return super(queue_name, klass, *args) unless pin && pin.enabled?

          # DEV: Do not set a service name
          #   Otherwise these spans will be grouped together with
          #   the other "resque" spans and be considered for the
          #   top level operation name
          pin.tracer.trace(Ext::SPAN_ENQUEUE) do |span|
            span.resource = klass.name
            span.set_tag(Ext::TAG_QUEUE, queue_name)
            span.set_tag(Ext::TAG_CLASS, klass.name)

            return super(queue_name, klass, *args)
          end
        end
      end
    end
  end
end
