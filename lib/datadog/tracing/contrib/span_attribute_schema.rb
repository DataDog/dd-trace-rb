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

        # TODO: implement function in all integrations with spankind
        def set_peer_service(span)
          set_peer_service?(span) && set_peer_service_from_source(span)
          # TODO: add logic for remap as long as the above expression is true
        end

        # set_peer_service?: checks to see if any edited peer.service tags exist so that they are not overwritten
        def set_peer_service?(span)
          ps = span.get_tag(Tracing::Metadata::Ext::TAG_PEER_SERVICE)
          if ps && (ps != '')

            # if peer.service is not equal to span.service we know it is edited
            if ps != span.service
              span.set_tag(Tracing::Metadata::Ext::TAG_PEER_SERVICE_SOURCE, Tracing::Metadata::Ext::TAG_PEER_SERVICE)
              return false
            end

            # if span.service is not the global service, we know it was changed to change the peer.service value
            if (ps == span.service) && (span.service != Datadog.configuration.service)
              span.set_tag(Tracing::Metadata::Ext::TAG_PEER_SERVICE_SOURCE, Tracing::Metadata::Ext::TAG_PEER_SERVICE)
              return false
            end
          end

          # only allow peer.service to be changed if it is an outbound span with the correct schema version
          if ((span.get_tag(Tracing::Metadata::Ext::TAG_KIND) == Tracing::Metadata::Ext::SpanKind::TAG_CLIENT) ||
            (span.get_tag(Tracing::Metadata::Ext::TAG_KIND) == Tracing::Metadata::Ext::SpanKind::TAG_PRODUCER)) &&
              (Datadog.configuration.tracing.span_attribute_schema ==
                  Tracing::Configuration::Ext::SpanAttributeSchema::VERSION_ONE)
            return true

            # TODO: add specific env var just for peer.service independent of v1
          end

          false
        end

        # set_peer_service_from_source: Implements the extraction logic to determine the peer.service value
        # based on the span type and a set of "precursor" tags.
        # Also sets the source of where the information for peer.service was extracted from
        # Returns a boolean if peer.service was successfully set or not
        def set_peer_service_from_source(span)
          case
          when span.get_tag(Aws::Ext::TAG_AWS_SERVICE)
            sources = Tracing::Contrib::Ext::SpanAttributeSchema::PEER_SERVICE_SOURCE_AWS
          when span.get_tag(Tracing::Contrib::Ext::DB::TAG_SYSTEM)
            sources = Tracing::Contrib::Ext::SpanAttributeSchema::PEER_SERVICE_SOURCE_DB
          when span.get_tag(Tracing::Contrib::Ext::Messaging::TAG_SYSTEM)
            sources = Tracing::Contrib::Ext::SpanAttributeSchema::PEER_SERVICE_SOURCE_MSG
          when span.get_tag(Tracing::Contrib::Ext::RPC::TAG_SYSTEM)
            sources = Tracing::Contrib::Ext::SpanAttributeSchema::PEER_SERVICE_SOURCE_RPC
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
            return true
          end
          false
        end
      end
    end
  end
end
