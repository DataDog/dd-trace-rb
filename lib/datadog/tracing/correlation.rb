require_relative '../core'

module Datadog
  module Tracing
    # Contains behavior for managing correlations with tracing
    # e.g. Retrieve a correlation to the current trace for logging, etc.
    module Correlation
      # Represents current trace state with key identifiers
      # @public_api
      class Identifier
        LOG_ATTR_ENV = 'dd.env'.freeze
        LOG_ATTR_SERVICE = 'dd.service'.freeze
        LOG_ATTR_SPAN_ID = 'dd.span_id'.freeze
        LOG_ATTR_TRACE_ID = 'dd.trace_id'.freeze
        LOG_ATTR_VERSION = 'dd.version'.freeze

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

        # @!visibility private
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
          @env = Core::Utils::SafeDup.frozen_or_dup(env || Datadog.configuration.env).freeze
          @service = Core::Utils::SafeDup.frozen_or_dup(service || Datadog.configuration.service).freeze
          @span_id = span_id || 0
          @span_name = Core::Utils::SafeDup.frozen_or_dup(span_name).freeze
          @span_resource = Core::Utils::SafeDup.frozen_or_dup(span_resource).freeze
          @span_service = Core::Utils::SafeDup.frozen_or_dup(span_service).freeze
          @span_type = Core::Utils::SafeDup.frozen_or_dup(span_type).freeze
          @trace_id = trace_id || 0
          @trace_name = Core::Utils::SafeDup.frozen_or_dup(trace_name).freeze
          @trace_resource = Core::Utils::SafeDup.frozen_or_dup(trace_resource).freeze
          @trace_service = Core::Utils::SafeDup.frozen_or_dup(trace_service).freeze
          @version = Core::Utils::SafeDup.frozen_or_dup(version || Datadog.configuration.version).freeze
        end

        def to_log_format
          @log_format ||= begin
            attributes = []
            attributes << "#{LOG_ATTR_ENV}=#{env}" unless env.nil?
            attributes << "#{LOG_ATTR_SERVICE}=#{service}"
            attributes << "#{LOG_ATTR_VERSION}=#{version}" unless version.nil?
            attributes << "#{LOG_ATTR_TRACE_ID}=#{trace_id}"
            attributes << "#{LOG_ATTR_SPAN_ID}=#{span_id}"
            attributes.join(' ')
          end
        end
      end

      module_function

      # Produces a CorrelationIdentifier from the TraceDigest provided
      #
      # DEV: can we memoize this object, give it can be common to
      # use a correlation multiple times, specially in the context of logging?
      # @!visibility private
      def identifier_from_digest(digest)
        return Identifier.new unless digest

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
end
