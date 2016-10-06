module Datadog
  module Instrument
    # some stuff
    module RailsFramework
      def self.start_render_template(*)
        tracer.trace('rails.render_template')
      end

      def self.start_render_partial(*)
        tracer.trace('rails.render_partial')
      end

      def self.render_template(_name, start, finish, _id, payload)
        # finish the tracing and update the execution time
        span = tracer.buffer.get
        # TODO: this should be normalized someway
        span.set_tag('rails.template_name', payload[:identifier])
        span.set_tag('rails.layout', payload[:layout])
        span.start_time = start
        span.finish_at(finish)
      end

      def self.render_partial(_name, start, finish, _id, payload)
        # finish the tracing and update the execution time
        span = tracer.buffer.get
        # TODO: this should be normalized someway
        span.set_tag('rails.template_name', payload[:identifier])
        span.start_time = start
        span.finish_at(finish)
      end
    end
  end
end
