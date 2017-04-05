module Datadog
  module Contrib
    module ActiveRecord
      # Patcher enables patching of 'active_record' module.
      # This is used in monkey.rb to manually apply patches
      module Patcher
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

              patch_active_record()

              @patched = true
            rescue
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

        def self.datadog_trace
          # TODO: Consider using patcher for Rails as well.
          # @tracer ||= defined?(::Rails) && ::Rails.configuration.datadog_trace
          @datadog_trace ||= defined?(::Sinatra) && ::Sinatra::Application.settings.datadog_tracer.cfg
        end

        def self.adapter_name
          @adapter_name ||= Datadog::Contrib::Rails::Utils.normalize_vendor(
            ::ActiveRecord::Base.connection_config[:adapter]
          )
        end

        def self.tracer
          @tracer ||= datadog_trace.fetch(:tracer)
        end

        def self.database_service
          @database_service ||= datadog_trace.fetch(:default_database_service, adapter_name)
        end

        def self.sql(_name, start, finish, _id, payload)
          span_type = Datadog::Ext::SQL::TYPE

          span = tracer.trace(
            "#{adapter_name}.query",
            resource: payload.fetch(:sql),
            service: database_service,
            span_type: span_type
          )

          # the span should have the query ONLY in the Resource attribute,
          # so that the ``sql.query`` tag will be set in the agent with an
          # obfuscated version
          span.span_type = Datadog::Ext::SQL::TYPE
          span.set_tag('active_record.db.vendor', adapter_name)
          span.start_time = start
          span.finish_at(finish)
        rescue StandardError => e
          Datadog::Tracer.log.error(e.message)
        end
      end
    end
  end
end
