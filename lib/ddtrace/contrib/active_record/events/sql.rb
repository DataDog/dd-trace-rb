require 'ddtrace/ext/net'
require 'ddtrace/contrib/analytics'
require 'ddtrace/contrib/active_record/ext'
require 'ddtrace/contrib/active_record/event'

module Datadog
  module Contrib
    module ActiveRecord
      module Events
        # Defines instrumentation for sql.active_record event
        module SQL
          include ActiveRecord::Event

          EVENT_NAME = 'sql.active_record'.freeze
          PAYLOAD_CACHE = 'CACHE'.freeze

          module_function

          def event_name
            self::EVENT_NAME
          end

          def span_name
            Ext::SPAN_SQL
          end

          def process(span, event, _id, payload)
            config = Utils.connection_config(payload[:connection], payload[:connection_id])
            settings = Datadog.configuration[:active_record, config]
            adapter_name = Datadog::Utils::Database.normalize_vendor(config[:adapter])
            service_name = if settings.service_name != Datadog::Utils::Database::VENDOR_DEFAULT
                             settings.service_name
                           else
                             adapter_name
                           end

            span.name = "#{adapter_name}.query"
            span.service = service_name
            span.resource = payload.fetch(:sql)
            span.span_type = Datadog::Ext::SQL::TYPE

            # Set analytics sample rate
            if Contrib::Analytics.enabled?(configuration[:analytics_enabled])
              Contrib::Analytics.set_sample_rate(span, configuration[:analytics_sample_rate])
            end

            # Find out if the SQL query has been cached in this request. This meta is really
            # helpful to users because some spans may have 0ns of duration because the query
            # is simply cached from memory, so the notification is fired with start == finish.
            cached = payload[:cached] || (payload[:name] == PAYLOAD_CACHE)

            span.set_tag(Ext::TAG_DB_VENDOR, adapter_name)
            span.set_tag(Ext::TAG_DB_NAME, config[:database])
            span.set_tag(Ext::TAG_DB_CACHED, cached) if cached
            span.set_tag(Datadog::Ext::NET::TARGET_HOST, config[:host]) if config[:host]
            span.set_tag(Datadog::Ext::NET::TARGET_PORT, config[:port]) if config[:port]
          rescue StandardError => e
            Datadog::Tracer.log.debug(e.message)
          end
        end
      end
    end
  end
end
