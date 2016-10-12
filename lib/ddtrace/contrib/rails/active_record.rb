module Datadog
  module Contrib
    module Rails
      # TODO[manu]: write docs
      module ActiveRecord
        def self.instrument
          # subscribe when the active record query has been processed
          ::ActiveSupport::Notifications.subscribe('sql.active_record') do |*args|
            sql(*args)
          end
        end

        def self.sql(_name, start, finish, _id, payload)
          tracer = ::Rails.configuration.datadog_trace.fetch(:tracer)
          adapter_name = ::ActiveRecord::Base.connection.adapter_name.downcase
          span = tracer.trace("#{adapter_name}.query", service: 'defaultdb', type: 'db')
          span.span_type = 'sql'
          span.set_tag('rails.db.vendor', adapter_name)
          span.set_tag('sql.query', payload.fetch(:sql))
          span.start_time = start
          span.finish_at(finish)
        rescue StandardError => e
          # TODO[manu]: better error handling
          puts e
        end
      end
    end
  end
end
