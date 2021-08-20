# typed: false
require 'ddtrace/ext/app_types'
require 'ddtrace/ext/integration'
require 'ddtrace/ext/net'
require 'ddtrace/ext/sql'
require 'ddtrace/contrib/analytics'
require 'ddtrace/contrib/mysql2/ext'

module Datadog
  module Contrib
    module Mysql2
      module Instrumentation
        # Mysql2::Client tracing
        module Client
          module_function

          def query(env)
            # Retrieve pin. Skip tracing if unavailable.
            client = get_client(env)
            datadog_pin = get_datadog_pin(client)
            return yield(env) unless client && datadog_pin

            sql, _options = env[:args]
            query_options = client.query_options

            datadog_pin.tracer.trace(Ext::SPAN_QUERY) do |span|
              span.resource = sql
              span.service = datadog_pin.service
              span.span_type = Datadog::Ext::SQL::TYPE

              # Tag as an external peer service
              span.set_tag(Datadog::Ext::Integration::TAG_PEER_SERVICE, span.service)

              # Set analytics sample rate
              if Datadog.configuration[:mysql2][:analytics_enabled]
                Contrib::Analytics.set_sample_rate(span, Datadog.configuration[:mysql2][:analytics_sample_rate])
              end

              span.set_tag(Ext::TAG_DB_NAME, query_options[:database])
              span.set_tag(Datadog::Ext::NET::TARGET_HOST, query_options[:host])
              span.set_tag(Datadog::Ext::NET::TARGET_PORT, query_options[:port])

              # Invoke original method
              yield(env)
            end
          end

          def get_client(env)
            return unless env[:self].instance_of?(::Mysql2::Client)

            env[:self]
          end

          def get_datadog_pin(client)
            # Only get a pin from a Mysql2::Client
            return unless client

            # Get existing pin or create a new one.
            if client.instance_variable_defined?(:@datadog_pin)
              client.instance_variable_get(:@datadog_pin)
            else
              client.instance_variable_set(
                :@datadog_pin,
                Datadog::Pin.new(
                  Datadog.configuration[:mysql2][:service_name],
                  app: Ext::APP,
                  app_type: Datadog::Ext::AppTypes::DB,
                  tracer: -> { Datadog.configuration[:mysql2][:tracer] }
                )
              )
            end
          end
        end
      end
    end
  end
end
