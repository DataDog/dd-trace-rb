require 'ddtrace/ext/integration'
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
            # caller_path = extract_caller_path(caller)
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

            # Tag as an external peer service
            span.set_tag(Datadog::Ext::Integration::TAG_PEER_SERVICE, span.service)

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
            # span.set_tag(Ext::SPAN_CALLER_STACK, caller_path) if caller_path.present?
          rescue StandardError => e
            Datadog.logger.debug(e.message)
          end

          private

          def extract_caller_path(callers)
            caller_path = callers
                          .select { |c| c =~ %r{^#{Rails.root}/(lib|app|scripts|config)} }
                          .map { |c| c.gsub Rails.root.to_s, '' }[0...10]

            # Handle cases when the db query is triggered from inside of a Rubygem
            caller_path = callers[0...10] if caller_path.nil?

            caller_path.join(",\n")
          end
        end
      end
    end
  end
end
