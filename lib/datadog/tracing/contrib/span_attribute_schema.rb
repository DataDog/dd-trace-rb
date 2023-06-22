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

        # set_peer_service?: returns boolean to reflect if peer.service should be set as long
        # This is to prevent overwriting of pre-existing peer.service tags
        def set_peer_service?(span)
          ps = span.get_tag(Tracing::Metadata::Ext::TAG_PEER_SERVICE)
          if ps && (ps != '')

            # In v0, peer.service is set directly equal to span.service by default.
            # That value is not the expected functionality here so we can overwrite that peer.service tag
            # assuming it is in the default state of being equal to the global service.
            #
            # If peer.service is not equal to span.service we know this value was explicitly set so we do not overwrite it
            if ps != span.service
              span.set_tag(Tracing::Metadata::Ext::TAG_PEER_SERVICE_SOURCE, Tracing::Metadata::Ext::TAG_PEER_SERVICE)
              return false
            end

            # There is a unique scenario where the user enables peer.service while in v0.
            # This means that the peer.service tag can be changed with span.service.
            # In order to respect that change, we check if span.service was actually modified or in its default state.
            # Thus if span.service is not equal to the global service,
            # we can assume the user changed it meaning that this peer.service value must stay.
            #
            # If span.service is not the global service, we know it was changed and we keep the peer.service value
            if (ps == span.service) && (span.service != Datadog.configuration.service)
              span.set_tag(Tracing::Metadata::Ext::TAG_PEER_SERVICE_SOURCE, Tracing::Metadata::Ext::TAG_PEER_SERVICE)
              return false
            end
          end

          # Check that peer.service is only set on spankind client/producer spans while v1 is enabled
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

          # outsource to each integration to make them provide it as a mandatory integration
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

          # make separate array and freeze it as constant and search separately
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
