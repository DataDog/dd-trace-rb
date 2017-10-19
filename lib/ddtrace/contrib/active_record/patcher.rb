module Datadog
  module Contrib
    module ActiveRecord
      # Patcher enables patching of 'active_record' module.
      # This is used in monkey.rb to manually apply patches
      module Patcher
        include Base
        register_as :active_record, auto_patch: false

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
          return Datadog.tracer unless datadog_trace
          @tracer ||= datadog_trace.fetch(:tracer)
        end

        def self.database_service
          @database_service ||= if defined?(::Sinatra)
                                  datadog_trace.fetch(:default_database_service, adapter_name())
                                else
                                  adapter_name()
                                end
          if @database_service
            tracer().set_service_info(@database_service, 'sinatra',
                                      Datadog::Ext::AppTypes::DB)
          end
          @database_service
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
          span.finish(finish)
        rescue StandardError => e
          Datadog::Tracer.log.error(e.message)
        end
      end
    end
  end
end
