# frozen_string_literal: true

require_relative 'ext'

module Datadog
  module Tracing
    module Contrib
      # Contains methods for fetching values according to span attributes schema
      module SpanAttributeSchema
        module_function

        # TODO: consolidate all db.name tags to 1 tag name and add to array here
        PEER_SERVICE_SOURCE_DB = Array[Tracing::Contrib::Ext::DB::TAG_INSTANCE].freeze

        # TODO: add kafka bootstrap servers tag
        PEER_SERVICE_SOURCE_MSG = Array[].freeze

        PEER_SERVICE_SOURCE_RPC = Array[Tracing::Contrib::Ext::RPC::TAG_SERVICE].freeze

        PEER_SERVICE_SOURCE_DEFAULT = Array[Tracing::Metadata::Ext::NET::TAG_DESTINATION_NAME,
          Tracing::Metadata::Ext::TAG_PEER_HOSTNAME,
          Tracing::Metadata::Ext::NET::TAG_TARGET_HOST,].freeze

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
          set_peer_service?(span) && set_peer_service_from_source(span, sources)
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
            if span.service != Datadog.configuration.service
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
        # based on the list of source tags passed as a parameter.
        #
        # If no values are found, it checks the default list for all spans before returning false for no result
        # Sets the source of where the information for peer.service was extracted from
        # Returns a boolean if peer.service was successfully set or not
        def set_peer_service_from_source(span, sources = [])
          # Find a possible peer.service source from the list of source tags passed in
          sources.each do |source|
            source_val = span.get_tag(source)
            next unless source_val && source_val != ''

            span.set_tag(Tracing::Metadata::Ext::TAG_PEER_SERVICE, source_val)
            span.set_tag(Tracing::Metadata::Ext::TAG_PEER_SERVICE_SOURCE, source)
            return true
          end

          # Fina a backup peer.service source from list of default sources
          PEER_SERVICE_SOURCE_DEFAULT.each do |default|
            source_val = span.get_tag(default)
            next unless source_val && source_val != ''

            span.set_tag(Tracing::Metadata::Ext::TAG_PEER_SERVICE, source_val)
            span.set_tag(Tracing::Metadata::Ext::TAG_PEER_SERVICE_SOURCE, default)
            return true
          end

          false
        end
      end
    end
  end
end
