require 'ddtrace/ext/sql'

require 'ddtrace/contrib/rails/utils'

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
          adapter_name = ::ActiveRecord::Base.connection_config[:adapter]
          adapter_name = Datadog::Contrib::Rails::Utils.normalize_vendor(adapter_name)
          span_type = Datadog::Ext::SQL::TYPE

          span = tracer.trace("#{adapter_name}.query", resource: payload.fetch(:sql), service: adapter_name, span_type: span_type)
          span.span_type = Datadog::Ext::SQL::TYPE
          span.set_tag(Datadog::Ext::SQL::QUERY, payload.fetch(:sql))
          span.set_tag('rails.db.vendor', adapter_name)
          span.start_time = start
          span.finish_at(finish)
        rescue StandardError => e
          Datadog::Tracer.log.error(e.message)
        end
      end
    end
  end
end
