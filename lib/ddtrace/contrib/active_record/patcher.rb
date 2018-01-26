module Datadog
  module Contrib
    module ActiveRecord
      # Patcher enables patching of 'active_record' module.
      module Patcher
        include Base
        register_as :active_record, auto_patch: false
        option :service_name
        option :tracer, default: Datadog.tracer

        @patched = false

        module_function

        # patched? tells whether patch has been successfully applied
        def patched?
          @patched
        end

        def patch
          if !@patched && defined?(::ActiveRecord)
            begin
              require 'ddtrace/contrib/rails/utils'
              require 'ddtrace/ext/sql'
              require 'ddtrace/ext/app_types'

              patch_active_record()

              @patched = true
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply Active Record integration: #{e}")
            end
          end

          @patched
        end

        def patch_active_record
          # subscribe when the active record query has been processed
          ::ActiveSupport::Notifications.subscribe('sql.active_record') do |*args|
            sql(*args)
          end
        end

        def self.adapter_name
          @adapter_name ||= Datadog::Contrib::Rails::Utils.adapter_name
        end

        def self.database_name
          @database_name ||= Datadog::Contrib::Rails::Utils.database_name
        end

        def self.adapter_host
          @adapter_host ||= Datadog::Contrib::Rails::Utils.adapter_host
        end

        def self.adapter_port
          @adapter_port ||= Datadog::Contrib::Rails::Utils.adapter_port
        end

        def self.database_service
          return @database_service if defined?(@database_service)

          @database_service = get_option(:service_name) || adapter_name
          get_option(:tracer).set_service_info(@database_service, 'active_record', Ext::AppTypes::DB)
          @database_service
        end

        def self.sql(_name, start, finish, _id, payload)
          span_type = Datadog::Ext::SQL::TYPE

          span = get_option(:tracer).trace(
            "#{adapter_name}.query",
            resource: payload.fetch(:sql),
            service: database_service,
            span_type: span_type
          )

          # Find out if the SQL query has been cached in this request. This meta is really
          # helpful to users because some spans may have 0ns of duration because the query
          # is simply cached from memory, so the notification is fired with start == finish.
          cached = payload[:cached] || (payload[:name] == 'CACHE')

          # the span should have the query ONLY in the Resource attribute,
          # so that the ``sql.query`` tag will be set in the agent with an
          # obfuscated version
          span.span_type = Datadog::Ext::SQL::TYPE
          span.set_tag('active_record.db.vendor', adapter_name)
          span.set_tag('active_record.db.name', database_name)
          span.set_tag('active_record.db.cached', cached) if cached
          span.set_tag('out.host', adapter_host)
          span.set_tag('out.port', adapter_port)
          span.start_time = start
          span.finish(finish)
        rescue StandardError => e
          Datadog::Tracer.log.error(e.message)
        end
      end
    end
  end
end
