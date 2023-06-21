# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      # Contains methods for fetching values according to span attributes schema
      module SpanAttributeSchema
        module_function

        def fetch_service_name(env, default)
          ENV.fetch(env) do
            if Datadog.configuration.tracing.span_attribute_schema ==
                Tracing::Configuration::Ext::SpanAttributeSchema::VERSION_ONE
              Datadog.configuration.service
            else
              default
            end
          end
        end

        def default_span_attribute_schema?
          Datadog.configuration.tracing.span_attribute_schema ==
            Tracing::Configuration::Ext::SpanAttributeSchema::DEFAULT_VERSION
        end

        # implement this function in all target spans/integrations with spankind
        def set_peer_service(span)
          should_set_peer_service(span) && set_peer_service_from_source(span)
          # if above
          # then remap + remapped from (SKIP)
          # else
          # debug that peer service could not be set
          # end
        end

        def should_set_peer_service(span)
          ps = span.get_tag(Tracing::Metadata::Ext::TAG_PEER_SERVICE)
          if ps && (ps != '')
            if ps != span.service
              span.set_tag(Tracing::Metadata::Ext::TAG_PEER_SERVICE_SOURCE, Tracing::Metadata::Ext::TAG_PEER_SERVICE)
              return false
            end

            if (ps == span.service) && (span.service != Datadog.configuration.service)
              span.set_tag(Tracing::Metadata::Ext::TAG_PEER_SERVICE_SOURCE, Tracing::Metadata::Ext::TAG_PEER_SERVICE)
              return false
            end
          end

          if ((span.get_tag(Tracing::Metadata::Ext::TAG_KIND) == Tracing::Metadata::Ext::SpanKind::TAG_CLIENT) ||
            (span.get_tag(Tracing::Metadata::Ext::TAG_KIND) == Tracing::Metadata::Ext::SpanKind::TAG_PRODUCER)) &&
              (Datadog.configuration.tracing.span_attribute_schema ==
                  Tracing::Configuration::Ext::SpanAttributeSchema::VERSION_ONE) # OR if env var is set
            return true
          end

          false
        end

        def set_peer_service_from_source(span)
          case
          when span.get_tag(Aws::Ext::TAG_AWS_SERVICE)
            sources = Array[Aws::Ext::TAG_QUEUE_NAME,
              Aws::Ext::TAG_TOPIC_NAME,
              Aws::Ext::TAG_STREAM_NAME,
              Aws::Ext::TAG_TABLE_NAME,
              Aws::Ext::TAG_BUCKET_NAME,
              Aws::Ext::TAG_RULE_NAME,
              Aws::Ext::TAG_STATE_MACHINE_NAME,]
          when span.get_tag(Tracing::Contrib::Ext::DB::TAG_SYSTEM)
            sources = Array[Tracing::Contrib::Ext::DB::TAG_INSTANCE] # DB_NAME tag?
          when span.get_tag(Tracing::Contrib::Ext::Messaging::TAG_SYSTEM)
            sources = Array[] # kafka bootstrap servers
          when span.get_tag(Tracing::Contrib::Ext::RPC::TAG_SYSTEM)
            sources = Array[Tracing::Contrib::Ext::RPC::TAG_SERVICE]
          else
            return false
          end
          sources <<
            Tracing::Metadata::Ext::NET::TAG_DESTINATION_NAME <<
            Tracing::Metadata::Ext::TAG_PEER_HOSTNAME <<
            Tracing::Metadata::Ext::NET::TAG_TARGET_HOST

          sources.each do |source|
            source_val = span.get_tag(source)
            next unless source_val && source_val != ''

            span.set_tag(Tracing::Metadata::Ext::TAG_PEER_SERVICE, source_val)
            span.set_tag(Tracing::Metadata::Ext::TAG_PEER_SERVICE_SOURCE, source)
            break
          end
          true
        end
      end
    end
  end
end
