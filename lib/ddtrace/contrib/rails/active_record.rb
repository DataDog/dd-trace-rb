module Datadog
  module Instrument
    # some stuff
    module RailsFramework
      def self.sql(_name, start, finish, _id, payload)
        tracer = Rails.configuration.datadog_trace[:tracer]
        adapter_name = ActiveRecord::Base.connection.adapter_name.downcase
        span = tracer.trace("#{adapter_name}.query", service: 'defaultdb', type: 'db')
        span.span_type = 'sql'
        span.set_tag('rails.db.vendor', adapter_name)
        span.set_tag('sql.query', payload[:sql])
        span.start_time = start
        span.finish_at(finish)
      end
    end
  end
end
