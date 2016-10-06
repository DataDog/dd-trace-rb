module Datadog
  module Instrument
    # some stuff
    module RailsFramework
      def self.start_processing(*)
        tracer = Rails.configuration.datadog_trace[:tracer]
        tracer.trace('rails.request', service: 'rails-app', type: 'web')
      end

      def self.process_action(_name, start, finish, _id, payload)
        tracer = Rails.configuration.datadog_trace[:tracer]
        span = tracer.buffer.get
        span.resource = "#{payload[:controller]}##{payload[:action]}"
        span.set_tag('http.url', payload[:path])
        span.set_tag('http.method', payload[:method])
        span.set_tag('http.status_code', payload[:status].to_s)
        span.set_tag('rails.route.action', payload[:action])
        span.set_tag('rails.route.controller', payload[:controller])
        span.start_time = start
        span.finish_at(finish)
      end
    end
  end
end
