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
              tracer.trace(Ext::SPAN_QUERY, span_options) do |span|
                begin
                  decorate!(span)
                  span.resource = query
                  span.span_type = Datadog::Ext::SQL::TYPE
                  span.set_tag(Ext::TAG_QUERY_ASYNC, false)
                rescue StandardError => e
                  Datadog.logger.debug("error preparing span for presto: #{e}")
                end

                super(query)
              end
            end

            def query(query, &blk)
              tracer.trace(Ext::SPAN_QUERY, span_options) do |span|
                begin
                  decorate!(span)
                  span.resource = query
                  span.span_type = Datadog::Ext::SQL::TYPE
                  span.set_tag(Ext::TAG_QUERY_ASYNC, !blk.nil?)
                rescue StandardError => e
                  Datadog.logger.debug("error preparing span for presto: #{e}")
                end

                super(query, &blk)
              end
            end

            def kill(query_id)
              tracer.trace(Ext::SPAN_KILL, span_options) do |span|
                begin
                  decorate!(span)
                  span.resource = Ext::SPAN_KILL
                  span.span_type = Datadog::Ext::AppTypes::DB
                  # ^ not an SQL type span, since there's no SQL query
                  span.set_tag(Ext::TAG_QUERY_ID, query_id)
                rescue StandardError => e
                  Datadog.logger.debug("error preparing span for presto: #{e}")
                end

                super(query_id)
              end
            end

            private

            def datadog_configuration
              Datadog.configuration[:presto]
            end

            def span_options
              {
                service: datadog_configuration[:service_name],
                app: Ext::APP,
                app_type: Datadog::Ext::AppTypes::DB
              }
            end

            def tracer
              datadog_configuration.tracer
            end

            def decorate!(span)
              set_nilable_tag!(span, :server, Datadog::Ext::NET::TARGET_HOST)
              set_nilable_tag!(span, :user, Ext::TAG_USER_NAME)
              set_nilable_tag!(span, :schema, Ext::TAG_SCHEMA_NAME)
              set_nilable_tag!(span, :catalog, Ext::TAG_CATALOG_NAME)
              set_nilable_tag!(span, :time_zone, Ext::TAG_TIME_ZONE)
              set_nilable_tag!(span, :language, Ext::TAG_LANGUAGE)
              set_nilable_tag!(span, :http_proxy, Ext::TAG_PROXY)
              set_nilable_tag!(span, :model_version, Ext::TAG_MODEL_VERSION)

              # Tag as an external peer service
              span.set_tag(Datadog::Ext::Integration::TAG_PEER_SERVICE, span.service)

              # Set analytics sample rate
              if Contrib::Analytics.enabled?(datadog_configuration[:analytics_enabled])
                Contrib::Analytics.set_sample_rate(span, datadog_configuration[:analytics_sample_rate])
              end
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
