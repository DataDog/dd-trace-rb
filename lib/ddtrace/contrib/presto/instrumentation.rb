require 'ddtrace/pin'
require 'ddtrace/ext/net'
require 'ddtrace/ext/sql'
require 'ddtrace/ext/app_types'
require 'ddtrace/contrib/presto/ext'

module Datadog
  module Contrib
    module Presto
      # Instrumentation for Presto integration
      module Instrumentation
        # Instrumentation for Presto::Client::Client
        module Client
          def self.included(base)
            base.send(:prepend, InstanceMethods)
          end

          # Instance methods for Presto::Client
          module InstanceMethods
            def run(query)
              datadog_pin.tracer.trace(Ext::SPAN_QUERY) do |span|
                decorate!(span)
                span.resource = query
                super(query)
              end
            end

            def query(query, &blk)
              datadog_pin.tracer.trace(Ext::SPAN_QUERY) do |span|
                decorate!(span)
                span.resource = query
                super(query, &blk)
              end
            end

            def kill(query_id)
              datadog_pin.tracer.trace(Ext::SPAN_KILL) do |span|
                decorate!(span)
                span.resource = Ext::SPAN_KILL
                span.set_tag(Ext::TAG_QUERY_ID, query_id)
                super(query_id)
              end
            end

            private

            def datadog_pin
              @datadog_pin ||= Datadog::Pin.new(
                Datadog.configuration[:presto][:service_name],
                app: Ext::APP,
                app_type: Datadog::Ext::AppTypes::DB,
                tracer: Datadog.configuration[:presto][:tracer]
              )
            end

            def decorate!(span)
              span.service = datadog_pin.service
              span.span_type = Datadog::Ext::SQL::TYPE

              set_nilable_tag!(span, :server, Datadog::Ext::NET::TARGET_HOST)
              set_nilable_tag!(span, :user, Ext::TAG_USER_NAME)
              set_nilable_tag!(span, :schema, Ext::TAG_SCHEMA_NAME)
              set_nilable_tag!(span, :catalog, Ext::TAG_CATALOG_NAME)
              set_nilable_tag!(span, :time_zone, Ext::TAG_TIME_ZONE)
              set_nilable_tag!(span, :language, Ext::TAG_LANGUAGE)
              set_nilable_tag!(span, :http_proxy, Ext::TAG_PROXY)
              set_nilable_tag!(span, :model_version, Ext::TAG_MODEL_VERSION)
            end

            def set_nilable_tag!(span, key, tag_name)
              @options[key].tap { |val| span.set_tag(tag_name, val) if val }
            end
          end
        end
      end
    end
  end
end
