require 'ddtrace/ext/sql'
require 'ddtrace/contrib/rails/utils'

module Datadog
  module Contrib
    module Rails
      # Code used to create and handle 'mysql.query', 'postgres.query', ... spans.
      module ActiveRecord
        include Datadog::Patcher

        def self.instrument
          # ActiveRecord is instrumented only if it's available
          return unless defined?(::ActiveRecord)

          do_once(:instrument) do
            # subscribe when the active record query has been processed
            ::ActiveSupport::Notifications.subscribe('sql.active_record') do |*args|
              sql(*args)
            end
          end

          if Datadog::Contrib::Rails::Patcher.active_record_instantiation_tracing_supported?
            # subscribe when the active record instantiates objects
            ::ActiveSupport::Notifications.subscribe('instantiation.active_record') do |*args|
              instantiation(*args)
            end
          end
        end

        def self.sql(_name, start, finish, _id, payload)
          tracer = Datadog.configuration[:rails][:tracer]
          database_service = Datadog.configuration[:rails][:database_service]
          connection_config = Datadog::Contrib::Rails::Utils.connection_config(payload[:connection_id])

          span = tracer.trace(
            "#{connection_config[:adapter_name]}.query",
            resource: payload.fetch(:sql),
            service: database_service,
            span_type: Datadog::Ext::SQL::TYPE
          )

          # Find out if the SQL query has been cached in this request. This meta is really
          # helpful to users because some spans may have 0ns of duration because the query
          # is simply cached from memory, so the notification is fired with start == finish.
          cached = payload[:cached] || (payload[:name] == 'CACHE')

          # the span should have the query ONLY in the Resource attribute,
          # so that the ``sql.query`` tag will be set in the agent with an
          # obfuscated version
          span.span_type = Datadog::Ext::SQL::TYPE
          span.set_tag('rails.db.vendor', connection_config[:adapter_name])
          span.set_tag('rails.db.name', connection_config[:database_name])
          span.set_tag('rails.db.cached', cached) if cached
          span.set_tag('out.host', connection_config[:adapter_host])
          span.set_tag('out.port', connection_config[:adapter_port])
          span.start_time = start
          span.finish(finish)
        rescue StandardError => e
          Datadog::Tracer.log.debug(e.message)
        end

        def self.instantiation(_name, start, finish, _id, payload)
          tracer = Datadog.configuration[:rails][:tracer]

          span = tracer.trace(
            'active_record.instantiation',
            resource: payload.fetch(:class_name),
            span_type: 'custom'
          )

          span.service = span.parent ? span.parent.service : Datadog.configuration[:rails][:service_name]
          span.set_tag('active_record.instantiation.class_name', payload.fetch(:class_name))
          span.set_tag('active_record.instantiation.record_count', payload.fetch(:record_count))
          span.start_time = start
          span.finish(finish)
        rescue StandardError => e
          Datadog::Tracer.log.debug(e.message)
        end
      end
    end
  end
end
