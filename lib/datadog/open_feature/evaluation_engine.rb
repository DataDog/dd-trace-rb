# frozen_string_literal: true

require "json"

require_relative "ext"
require_relative "noop_evaluator"
require_relative "native_evaluator"
require_relative "resolution_details"
require_relative "../core/utils/only_once"

module Datadog
  module OpenFeature
    # This class performs the evaluation of the feature flag
    class EvaluationEngine
      # Steep: https://github.com/soutaro/steep/issues/1880
      ReconfigurationError = Class.new(StandardError) # steep:ignore IncompatibleAssignment

      ALLOWED_TYPES = %i[boolean string number float integer object].freeze

      RAW_DATA_WARNING = "Feature Flags: debug logging is enabled, so feature flag logs include raw evaluation data " \
        "(targeting keys, evaluation context attributes, flag values, and default values) that may contain " \
        "personal or sensitive information. Unset DD_TRACE_DEBUG when you no longer need it."

      def initialize(reporter, telemetry:, logger:)
        @reporter = reporter
        @telemetry = telemetry
        @logger = logger
        @raw_data_warning = Core::Utils::OnlyOnce.new

        @evaluator = NoopEvaluator.new(nil)
      end

      def fetch_value(flag_key, default_value:, expected_type:, evaluation_context: nil)
        # Pre-bound to the safe default so the rescue below can still read it if the
        # evaluator read itself raises.
        observe_full_evaluation_data = false
        # Snapshot the evaluator once: a concurrent reconfigure! must not retroactively
        # apply a different environment's full-evaluation-data policy to this evaluation.
        evaluator = @evaluator
        observe_full_evaluation_data = evaluator.observe_full_evaluation_data == true

        unless ALLOWED_TYPES.include?(expected_type)
          message = "unknown type #{expected_type.inspect}, allowed types #{ALLOWED_TYPES.join(", ")}"
          result = ResolutionDetails.build_error(
            value: default_value, error_code: Ext::UNKNOWN_TYPE, error_message: message,
          )

          return with_observe_full_evaluation_data(result, observe_full_evaluation_data)
        end

        context = evaluation_context&.fields.to_h
        result = evaluator.get_assignment(
          flag_key, default_value: default_value, context: context, expected_type: expected_type
        )

        result = with_observe_full_evaluation_data(result, observe_full_evaluation_data)
        log_resolution(flag_key, expected_type, result)

        @reporter.report(result, flag_key: flag_key, context: evaluation_context)

        result
      rescue => e
        @telemetry.report(e, description: "OpenFeature: Failed to fetch flag value")
        log_resolution_failure(flag_key, e)

        result = ResolutionDetails.build_error(
          value: default_value, error_code: Ext::GENERAL, error_message: "#{e.class}: #{e.message}",
        )
        # `== true` is load-bearing: Steep types this local as `(nil | bool)` in a rescue
        # body, and coercing at the use site is what narrows it to `bool`.
        with_observe_full_evaluation_data(result, observe_full_evaluation_data == true)
      end

      # NOTE: In a currect implementation configuration is expected to be a raw
      #       JSON string containing feature flags (straight from the remote config)
      #       in the format expected by `libdatadog` without any modifications
      def reconfigure!(configuration)
        if configuration.nil?
          @logger.debug("Feature Flags: configuration removed")

          return @evaluator = NoopEvaluator.new(configuration)
        end

        @evaluator = NativeEvaluator.new(configuration)
        @logger.debug { "Feature Flags: configuration applied; #{configuration_summary(configuration)}" }
      rescue => e
        message = "OpenFeature: Failed to reconfigure, reverting to the previous configuration"

        @logger.error("#{message}, #{e.class}: #{e.message}")
        @telemetry.report(e, description: "#{message} (#{e.class})")

        raise ReconfigurationError, "#{e.class}: #{e.message}"
      end

      # Public so Component can warn before handing out DebugLoggingHook, which logs raw data.
      def warn_raw_data_logging
        return unless @logger.debug?

        @raw_data_warning.run { @logger.warn(RAW_DATA_WARNING) }
      end

      private

      # The SDK can still replace this result, for example on a type mismatch; DebugLoggingHook logs the final one.
      def log_resolution(flag_key, expected_type, result)
        @logger.debug do
          warn_raw_data_logging
          "Feature Flags: provider resolved #{flag_key.inspect}: type=#{expected_type}, " \
            "value=#{result.value.inspect}, variant=#{result.variant.inspect}, reason=#{result.reason.inspect}, " \
            "allocation=#{result.allocation_key.inspect}, serial_id=#{result.serial_id.inspect}, " \
            "error_code=#{result.error_code.inspect}, error_message=#{result.error_message.inspect}"
        end
      end

      def log_resolution_failure(flag_key, error)
        @logger.debug do
          warn_raw_data_logging
          "Feature Flags: provider failed to resolve #{flag_key.inspect}: #{error.class}: #{error.message}; " \
            "returning the default value"
        end
      end

      def configuration_summary(configuration)
        payload = begin
          JSON.parse(configuration)
        rescue JSON::NestingError
          # Native parsing accepts deeper JSON than Ruby's default nesting limit.
          return "received payload metadata unavailable: JSON nesting exceeds the diagnostic parser limit"
        end
        return "received payload metadata unavailable: expected a JSON object" unless payload.is_a?(Hash)

        flags = payload["flags"]
        environment = payload["environment"]
        environment_name = environment["name"] if environment.is_a?(Hash)
        flag_count = flags.is_a?(Hash) ? "flag_count=#{flags.size}" : "flag_count is not specified"
        environment_summary = environment_name ? "environment=#{environment_name.inspect}" : "environment is not specified"
        created_at = payload["createdAt"]
        creation_summary = created_at ? "created_at=#{created_at.inspect}" : "created_at is not specified"

        "received payload: #{flag_count}, #{environment_summary}, #{creation_summary}; " \
          "individual flags may still fail evaluation"
      end

      # Stamps observe_full_evaluation_data onto the result metadata so the hook
      # reads it from the event, not live config.
      def with_observe_full_evaluation_data(result, observe_full_evaluation_data)
        result = result.dup if result.frozen?
        metadata = result.flag_metadata ||= {}
        metadata[Ext::METADATA_OBSERVE_FULL_EVALUATION_DATA] = observe_full_evaluation_data
        result
      end
    end
  end
end
