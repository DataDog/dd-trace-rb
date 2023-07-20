# frozen_string_literal: true

require_relative 'ext'

module Datadog
  module Tracing
    module Contrib
      # Contains methods for fetching values according to span attributes schema
      module SpanAttributeSchema
        module_function

        def default_span_attribute_schema?
          Datadog.configuration.tracing.span_attribute_schema ==
            Tracing::Configuration::Ext::SpanAttributeSchema::DEFAULT_VERSION
        end

        def active_version
          case Datadog.configuration.tracing.span_attribute_schema
          when 'v1'
            V1
          else
            V0 # Default Version
          end
        end

        def fetch_service_name(env, default)
          active_version.fetch_service_name(env, default)
        end

        def set_peer_service!(span, sources)
          active_version.set_peer_service!(span, sources)
        end

        private_class_method :active_version

        # Contains interface of methods to be implemented
        module Base
          REFLEXIVE_SOURCES = [Tracing::Metadata::Ext::TAG_PEER_SERVICE].freeze
          NO_SOURCE = [].freeze
          IMPLEMENT_ERROR = 'SpanAttributeSchema Version must implement fetch_service_name'

          def self.extended(base)
            base.private_class_method :not_empty_tag?, :set_peer_service_from_source, :filter_peer_service_sources
          end

          def fetch_service_name(_env, _default)
            raise NotImplementedError, IMPLEMENT_ERROR
          end

          def set_peer_service!(span, sources)
            # Acquire all peer.service values as well as any potential remapping
            peer_service_val, peer_service_source = set_peer_service_from_source(span, sources)
            remap_val = Datadog.configuration.tracing.peer_service_mapping[peer_service_val]

            # Only continue to setting peer.service if actual source is found
            return false unless peer_service_source

            span.set_tag(Tracing::Contrib::Ext::Metadata::TAG_PEER_SERVICE_SOURCE, peer_service_source)

            # Set peer.service to remapped value if found otherwise normally set peer.service
            if remap_val
              span.set_tag(Tracing::Metadata::Ext::TAG_PEER_SERVICE, remap_val)
              span.set_tag(Tracing::Contrib::Ext::Metadata::TAG_PEER_SERVICE_REMAP, peer_service_val)
            else
              span.set_tag(Tracing::Metadata::Ext::TAG_PEER_SERVICE, peer_service_val)
            end
            true
          end

          # set_peer_service_from_source: Implements the extraction logic to determine the peer.service value
          # based on the list of source tags passed as a parameter.
          #
          # If no values are found, it checks the default list for all spans before returning false for no result
          # Sets the source of where the information for peer.service was extracted from
          # Returns a peer.service value if successfully set or not
          def set_peer_service_from_source(span, sources = [])
            # Filter out sources based on existence of peer.service tag
            sources = filter_peer_service_sources(span, sources)

            # Find a possible peer.service source from the list of source tags passed in
            sources.each do |source|
              source_val = span.get_tag(source)
              next unless not_empty_tag?(source_val)

              return source_val, source
            end
            false
          end

          # filter_peer_service_sources: returns filtered sources based on existence of peer.service tag
          # If peer.service exists, we do not read from any other source rather use peer.service as source
          # This is to prevent overwriting of pre-existing peer.service tags
          def filter_peer_service_sources(span, sources)
            ps = span.get_tag(Tracing::Metadata::Ext::TAG_PEER_SERVICE)
            # Do not override existing peer.service tag if it exists based on schema version
            return REFLEXIVE_SOURCES if not_empty_tag?(ps)

            # Check that peer.service is only set on spankind client/producer spans
            if (span.get_tag(Tracing::Metadata::Ext::TAG_KIND) == Tracing::Metadata::Ext::SpanKind::TAG_CLIENT) ||
                (span.get_tag(Tracing::Metadata::Ext::TAG_KIND) == Tracing::Metadata::Ext::SpanKind::TAG_PRODUCER)
              return sources
            end

            NO_SOURCE
          end

          def not_empty_tag?(tag)
            tag && (tag != '')
          end
        end

        # Contains implementation of methods specific to v0
        module V0
          extend Base

          module_function

          def fetch_service_name(env, default)
            ENV.fetch(env) do
              return Datadog.configuration.service if Datadog.configuration.tracing.global_default_service_name.enabled

              default
            end
          end
        end

        # Contains implementation of methods specific to v1
        module V1
          extend Base

          module_function

          def fetch_service_name(env, _)
            ENV.fetch(env) { Datadog.configuration.service }
          end
        end
      end
    end
  end
end
