require 'ddtrace/ext/sql'
require 'ddtrace/ext/app_types'
require 'ddtrace/contrib/active_record/utils'
require 'ddtrace/contrib/active_support/notifications/subscriber'

module Datadog
  module Contrib
    module ActiveRecord
      # Patcher enables patching of 'active_record' module.
      module Patcher
        include Base
        include ActiveSupport::Notifications::Subscriber

        NAME_SQL = 'sql.active_record'.freeze
        NAME_INSTANTIATION = 'instantiation.active_record'.freeze
        DEFAULT_FLAGS = {
          trace_instantiation_events: true,
          trace_sql_events: true
        }.freeze

        register_as :active_record, auto_patch: false
        option :service_name, depends_on: [:tracer] do |value|
          (value || Utils.adapter_name).tap do |v|
            get_option(:tracer).set_service_info(v, 'active_record', Ext::AppTypes::DB)
          end
        end
        option :orm_service_name
        option :flags, setter: ->(value) { DEFAULT_FLAGS.merge(value) }, default: DEFAULT_FLAGS
        option :tracer, default: Datadog.tracer do |value|
          (value || Datadog.tracer).tap do |v|
            # Make sure to update tracers of all subscriptions
            subscriptions.each do |subscription|
              subscription.tracer = v
            end
          end
        end

        @patched = false

        on_subscribe do
          # sql.active_record
          if get_option(:flags)[:trace_sql_events]
            subscribe(
              self::NAME_SQL,                         # Event name
              'active_record.sql',                    # Span name
              { service: get_option(:service_name) }, # Span options
              get_option(:tracer),                    # Tracer
              &method(:sql)                           # Handler
            )
          end

          # instantiation.active_record
          if get_option(:flags)[:trace_instantiation_events] && instantiation_tracing_supported?
            subscribe(
              self::NAME_INSTANTIATION,               # Event name
              'active_record.instantiation',          # Span name
              { service: get_option(:service_name) }, # Span options
              get_option(:tracer),                    # Tracer
              &method(:instantiation)                 # Handler
            )
          end
        end

        module_function

        # patched? tells whether patch has been successfully applied
        def patched?
          @patched
        end

        def patch
          if !@patched && defined?(::ActiveRecord)
            begin
              subscribe!
              @patched = true
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply Active Record integration: #{e}")
            end
          end

          @patched
        end

        def instantiation_tracing_supported?
          Gem.loaded_specs['activerecord'] \
            && Gem.loaded_specs['activerecord'].version >= Gem::Version.new('4.2')
        end

        def sql(span, event, _id, payload)
          connection_config = Utils.connection_config(payload[:connection_id])
          span.name = "#{connection_config[:adapter_name]}.query"
          span.service = get_option(:service_name)
          span.resource = payload.fetch(:sql)
          span.span_type = Datadog::Ext::SQL::TYPE

          # Find out if the SQL query has been cached in this request. This meta is really
          # helpful to users because some spans may have 0ns of duration because the query
          # is simply cached from memory, so the notification is fired with start == finish.
          cached = payload[:cached] || (payload[:name] == 'CACHE'.freeze)

          span.set_tag('active_record.db.vendor'.freeze, connection_config[:adapter_name])
          span.set_tag('active_record.db.name'.freeze, connection_config[:database_name])
          span.set_tag('active_record.db.cached'.freeze, cached) if cached
          span.set_tag('out.host'.freeze, connection_config[:adapter_host])
          span.set_tag('out.port'.freeze, connection_config[:adapter_port])
        rescue StandardError => e
          Datadog::Tracer.log.debug(e.message)
        end

        def instantiation(span, event, _id, payload)
          # Inherit service name from parent, if available.
          span.service = if get_option(:orm_service_name)
                           get_option(:orm_service_name)
                         elsif span.parent
                           span.parent.service
                         else
                           'active_record'.freeze
                         end

          span.resource = payload.fetch(:class_name)
          span.span_type = 'custom'.freeze
          span.set_tag('active_record.instantiation.class_name'.freeze, payload.fetch(:class_name))
          span.set_tag('active_record.instantiation.record_count'.freeze, payload.fetch(:record_count))
        rescue StandardError => e
          Datadog::Tracer.log.debug(e.message)
        end
      end
    end
  end
end
