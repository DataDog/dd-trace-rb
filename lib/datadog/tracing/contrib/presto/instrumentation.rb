require_relative '../../metadata/ext'
require_relative 'ext'

module Datadog
  module Tracing
    module Contrib
      module Presto
        # Instrumentation for Presto integration
        module Instrumentation
          # Instrumentation for Presto::Client::Client
          module Client
            def self.included(base)
              base.prepend(InstanceMethods)
            end

            # Instance methods for Presto::Client
            module InstanceMethods
              def run(query)
                Tracing.trace(
                  Ext::SPAN_QUERY,
                  service: datadog_configuration[:service_name]
                ) do |span|
                  begin
                    decorate!(span, Ext::TAG_OPERATION_QUERY)
                    span.resource = query
                    span.span_type = Tracing::Metadata::Ext::SQL::TYPE
                    span.set_tag(Ext::TAG_QUERY_ASYNC, false)
                  rescue StandardError => e
                    Datadog.logger.debug("error preparing span for presto: #{e}")
                  end

                  super(query)
                end
              end

              def query(query, &blk)
                Tracing.trace(
                  Ext::SPAN_QUERY,
                  service: datadog_configuration[:service_name]
                ) do |span|
                  begin
                    decorate!(span, Ext::TAG_OPERATION_QUERY)
                    span.resource = query
                    span.span_type = Tracing::Metadata::Ext::SQL::TYPE
                    span.set_tag(Ext::TAG_QUERY_ASYNC, !blk.nil?)
                  rescue StandardError => e
                    Datadog.logger.debug("error preparing span for presto: #{e}")
                  end

                  super(query, &blk)
                end
              end

              def kill(query_id)
                Tracing.trace(
                  Ext::SPAN_KILL,
                  service: datadog_configuration[:service_name]
                ) do |span|
                  begin
                    decorate!(span, Ext::TAG_OPERATION_KILL)
                    span.resource = Ext::SPAN_KILL
                    span.span_type = Tracing::Metadata::Ext::AppTypes::TYPE_DB
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
                Datadog.configuration.tracing[:presto]
              end

              def decorate!(span, operation)
                span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT)
                span.set_tag(Tracing::Metadata::Ext::TAG_OPERATION, operation)
                span.set_tag(Tracing::Metadata::Ext::TAG_KIND, Tracing::Metadata::Ext::SpanKind::TAG_CLIENT)

                span.set_tag(Contrib::Ext::DB::TAG_SYSTEM, Ext::TAG_SYSTEM)

                if (host_port = @options[:server])
                  host, port = Core::Utils.extract_host_port(host_port)
                  if host && port
                    span.set_tag(Tracing::Metadata::Ext::NET::TAG_TARGET_HOST, host)
                    span.set_tag(Tracing::Metadata::Ext::NET::TAG_TARGET_PORT, port)

                    span.set_tag(Tracing::Metadata::Ext::TAG_PEER_HOSTNAME, host)
                  else
                    span.set_tag(Tracing::Metadata::Ext::NET::TAG_TARGET_HOST, host_port)
                    span.set_tag(Tracing::Metadata::Ext::TAG_PEER_HOSTNAME, host_port)
                  end
                end

                set_nilable_tag!(span, :user, Ext::TAG_USER_NAME)
                set_nilable_tag!(span, :schema, Ext::TAG_SCHEMA_NAME)
                set_nilable_tag!(span, :catalog, Ext::TAG_CATALOG_NAME)
                set_nilable_tag!(span, :time_zone, Ext::TAG_TIME_ZONE)
                set_nilable_tag!(span, :language, Ext::TAG_LANGUAGE)
                set_nilable_tag!(span, :http_proxy, Ext::TAG_PROXY)
                set_nilable_tag!(span, :model_version, Ext::TAG_MODEL_VERSION)

                # Tag as an external peer service
                span.set_tag(Tracing::Metadata::Ext::TAG_PEER_SERVICE, span.service)

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
end
