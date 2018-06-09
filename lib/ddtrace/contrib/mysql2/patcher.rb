module Datadog
  module Contrib
    module Mysql2
      # Patcher enables patching of 'mysql2' client.
      module Patcher
        include Base
        register_as :mysql2

        option :service_name, default: 'mysql2'
        option :tracer, default: Datadog.tracer

        @patched = false

        def self.patch
          return @patched if patched?

          require 'ddtrace/ext/app_types'
          require 'ddtrace/ext/sql'

          patch_mysql2_client()

          @patched = true
        rescue => e
          Tracer.log.error("Unable to apply mysql2 integration: #{e}")
          @patched
        end

        def self.patched?
          @patched
        end

        private_class_method

        def self.patch_mysql2_client
          ::Mysql2::Client.class_eval do
            def datadog_pin
              @datadog_pin ||=
                Datadog::Pin.new(
                  Datadog.configuration[:mysql2][:service_name],
                  app: 'mysql2',
                  app_type: Datadog::Ext::AppTypes::DB,
                  tracer: Datadog.configuration[:mysql2][:tracer]
                )
            end

            alias_method :query_without_datadog, :query
            remove_method :query
            def query(sql, options = {})
              pin = datadog_pin

              unless pin && pin.tracer && pin.tracer.enabled
                return query_without_datadog(sql, options)
              end

              response = nil
              pin.tracer.trace('mysql2.query') do |span|
                span.resource = sql
                span.service = pin.service
                span.span_type = Datadog::Ext::SQL::TYPE
                span.set_tag('mysql2.db.name', query_options[:database])
                span.set_tag('out.host', query_options[:host])
                span.set_tag('out.port', query_options[:port])
                response = query_without_datadog(sql, options)
              end

              response
            end
          end
        end
      end
    end
  end
end
