# typed: false
require 'ddtrace/ext/correlation'
require 'datadog/core/environment/variable_helpers'

module Datadog
  # Contains behavior for managing correlations with tracing
  # e.g. Retrieve a correlation to the current trace for logging, etc.
  module Correlation
    # Represents current trace state with key identifiers
    class Identifier
      attr_reader \
        :env,
        :service,
        :span_id,
        :span_name,
        :span_resource,
        :span_service,
        :span_type,
        :trace_id,
        :trace_name,
        :trace_resource,
        :trace_service,
        :version

      # rubocop:disable Metrics/CyclomaticComplexity
      # rubocop:disable Metrics/PerceivedComplexity
      def initialize(
        env: nil,
        service: nil,
        span_id: nil,
        span_name: nil,
        span_resource: nil,
        span_service: nil,
        span_type: nil,
        trace_id: nil,
        trace_name: nil,
        trace_resource: nil,
        trace_service: nil,
        version: nil
      )
        # Dup and freeze strings so they aren't modified by reference.
        @env = env || Datadog.configuration.env
        @service = service || Datadog.configuration.service
        @span_id = span_id || 0
        @span_name = span_name && span_name.dup.freeze
        @span_resource = span_resource && span_resource.dup.freeze
        @span_service = span_service && span_service.dup.freeze
        @span_type = span_type && span_type.dup.freeze
        @trace_id = trace_id || 0
        @trace_name = trace_name && trace_name.dup.freeze
        @trace_resource = trace_resource && trace_resource.dup.freeze
        @trace_service = trace_service && trace_service.dup.freeze
        @version = version || Datadog.configuration.version

        # Finish freezing globals
        @service = @service.dup.freeze unless @service.nil?
        @env = @env.dup.freeze unless @env.nil?
        @version = @version.dup.freeze unless @version.nil?
      end
      # rubocop:enable Metrics/CyclomaticComplexity
      # rubocop:enable Metrics/PerceivedComplexity

      def to_log_format
        @log_format ||= begin
          attributes = []
          attributes << "#{Ext::Correlation::ATTR_ENV}=#{env}" unless env.nil?
          attributes << "#{Ext::Correlation::ATTR_SERVICE}=#{service}"
          attributes << "#{Ext::Correlation::ATTR_VERSION}=#{version}" unless version.nil?
          attributes << "#{Ext::Correlation::ATTR_TRACE_ID}=#{trace_id}"
          attributes << "#{Ext::Correlation::ATTR_SPAN_ID}=#{span_id}"
          attributes.join(' ')
        end
      end
    end

    module_function

    # Produces a CorrelationIdentifier from the TraceDigest provided
    #
    # DEV: can we memoize this object, give it can be common to
    # use a correlation multiple times, specially in the context of logging?
    def identifier_from_digest(digest)
      return Identifier.new.freeze unless digest

      Identifier.new(
        span_id: digest.span_id,
        span_name: digest.span_name,
        span_resource: digest.span_resource,
        span_service: digest.span_service,
        span_type: digest.span_type,
        trace_id: digest.trace_id,
        trace_name: digest.trace_name,
        trace_resource: digest.trace_resource,
        trace_service: digest.trace_service
      )
    end
  end
end
