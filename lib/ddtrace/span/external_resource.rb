require 'ddtrace/ext/app_types'
require 'ddtrace/ext/http'

module Datadog
  class Span
    # Extension for Datadog::Span that tracks if this span
    # represents a unit of work performed by this application
    # or an external resource being indirectly measured
    # (e.g. SQL, Redis, outbound HTTP request).
    module ExternalResource
      attr_writer :external_resource

      # Span types of known to represent an internal application trace
      INTERNAL_APPLICATION_SPAN_TYPES = [
        Datadog::Ext::AppTypes::CUSTOM,
        Datadog::Ext::AppTypes::WEB,
        Datadog::Ext::AppTypes::WORKER,
        Datadog::Ext::HTTP::TEMPLATE
      ].freeze

      # Computes if this span represents an external resource by
      # first checking if +span.external_resource+ was explicitly set.
      # If so, use that value.
      #
      # Else, check if +span.span_type+ is a span type known to
      # represent internal application work.
      # If so, return +false+, otherwise return +true+.
      #
      # @return [Boolean] true if this span represents work performed outside of this application
      def external_resource?
        return @external_resource if defined?(@external_resource)
        return false unless span_type

        !INTERNAL_APPLICATION_SPAN_TYPES.include?(span_type)
      end
    end
  end
end
