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


        def should_set_peer_service(span)
          if span.get_tag(Tracing::Metadata::Ext::TAG_PEER_SERVICE)
            return false
          end

          if (span.get_tag(Tracing::Metadata::Ext::TAG_KIND) == Tracing::Metadata::Ext::SpanKind::TAG_CLIENT or
            span.get_tag(Tracing::Metadata::Ext::TAG_KIND) == Tracing::Metadata::Ext::SpanKind::TAG_PRODUCER) and
            Datadog.configuration.tracing.span_attribute_schema ==
              Tracing::Configuration::Ext::SpanAttributeSchema::VERSION_ONE
            return true
          end
          false
        end

        #implement this function in all target spans/integrations with spankind
        def set_peer_service(span)
          if should_set_peer_service(span) and set_peer_service_from_source(span)
            # else remap + remapped from (SKIP)
          else
            # debug that peer service could not be set
          end


        end


        def set_peer_service_from_source(span)
          case
            when span.get_tag(Aws::Ext::TAG_AWS_SERVICE)
              sources = Array["queuename",
                           "topicname",
                           "streamname",
                           "tablename",
                           "bucketname"]
            #when span.get_tag(DB_SYSTEM)
            #when span.get_tag(MESSAGING_SYSTEM)
            #when span.get_tag(RPC)
          else
            return false
          end
          sources.append(Tracing::Metadata::Ext::NET::TAG_DESTINATION_NAME, Tracing::Metadata::Ext::TAG_PEER_HOSTNAME,
                        Tracing::Metadata::Ext::NET::TAG_TARGET_HOST)

          for source in sources
            sourceVal = span.get_tag(source)
            if sourceVal
              span.set_tag(Tracing::Metadata::Ext::TAG_PEER_SERVICE, sourceVal)
              #set source tag here as well
            end
          end
          # set tag + source if found else return nothing
          # return tag value
        end
      end
    end
  end
end
