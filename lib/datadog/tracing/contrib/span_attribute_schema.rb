# frozen_string_literal: true

require_relative 'ext'

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
        def set_peer_service(span, sources)
          set_peer_service_from_source(span, sources)
          # TODO: add logic for remap as long as the above expression is true
        end

        # set_peer_service?: returns boolean to reflect if peer.service should be set as long
        # This is to prevent overwriting of pre-existing peer.service tags
        def set_peer_service?(span)
          # Check if peer.service is set
          if span.service != Datadog.configuration.service
            if not_empty_tag?(span.get_tag(Tracing::Metadata::Ext::TAG_PEER_SERVICE))
              span.set_tag(
                Tracing::Contrib::Ext::Metadata::TAG_PEER_SERVICE_SOURCE,
                Tracing::Metadata::Ext::TAG_PEER_SERVICE
              )
            end
          else
            span.set_tag(Tracing::Metadata::Ext::TAG_PEER_SERVICE, span.service)
            span.set_tag(Tracing::Contrib::Ext::Metadata::TAG_PEER_SERVICE_SOURCE, Tracing::Metadata::Ext::TAG_PEER_SERVICE)
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
        # based on the list of source tags passed as a parameter.
        #
        # If no values are found, it checks the default list for all spans before returning false for no result
        # Sets the source of where the information for peer.service was extracted from
        # Returns a boolean if peer.service was successfully set or not
        def set_peer_service_from_source(span, sources = [])
          return false unless set_peer_service?(span)

          # Find a possible peer.service source from the list of source tags passed in
          sources.each do |source|
            source_val = span.get_tag(source)
            next unless not_empty_tag?(source_val)

            span.set_tag(Tracing::Metadata::Ext::TAG_PEER_SERVICE, source_val)
            span.set_tag(Tracing::Contrib::Ext::Metadata::TAG_PEER_SERVICE_SOURCE, source)
            return true
          end
          false
        end

        def not_empty_tag?(tag)
          tag && (tag != '')
        end
      end
    end
  end
end
