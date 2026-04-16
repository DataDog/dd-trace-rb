# frozen_string_literal: true

module Datadog
  module OpenFeature
    module Metrics
      # Records flag evaluation metrics via OpenTelemetry
      class FlagEvalMetrics
        METER_NAME = 'ddtrace.openfeature'
        METRIC_NAME = 'feature_flag.evaluations'
        METRIC_UNIT = '{evaluation}'
        METRIC_DESCRIPTION = 'Number of feature flag evaluations'

        ATTR_FLAG_KEY = 'feature_flag.key'
        ATTR_VARIANT = 'feature_flag.result.variant'
        ATTR_REASON = 'feature_flag.result.reason'
        ATTR_ALLOCATION_KEY = 'feature_flag.result.allocation_key'
        ATTR_ERROR_TYPE = 'error.type'

        ERROR_TYPE_MAP = {
          'FLAG_NOT_FOUND' => 'flag_not_found',
          'TYPE_MISMATCH' => 'type_mismatch',
          'PARSE_ERROR' => 'parse_error',
          'PROVIDER_NOT_READY' => 'provider_not_ready',
          'TARGETING_KEY_MISSING' => 'targeting_key_missing',
          'INVALID_CONTEXT' => 'invalid_context',
          'GENERAL' => 'general',
          'PROVIDER_FATAL' => 'general',
          'UNKNOWN_TYPE' => 'general',
        }.freeze

        REASON_MAP = {
          'TARGETING_MATCH' => 'targeting_match',
          'ERROR' => 'error',
          'DEFAULT' => 'default',
          'DISABLED' => 'disabled',
          'SPLIT' => 'split',
          'STATIC' => 'static',
          'UNKNOWN' => 'unknown',
        }.freeze

        EXCLUDE_ALLOCATION_KEY_REASONS = %w[ERROR DEFAULT DISABLED].freeze

        def initialize(telemetry:, logger:)
          @telemetry = telemetry
          @logger = logger
          @counter = nil
          @mutex = Mutex.new
        end

        def record(flag_key, variant:, reason:, error_code: nil, allocation_key: nil)
          counter = get_or_create_counter
          return unless counter

          attributes = build_attributes(
            flag_key,
            variant: variant,
            reason: reason,
            error_code: error_code,
            allocation_key: allocation_key,
          )
          counter.add(1, attributes: attributes)
        rescue => e
          @logger.debug { "OpenFeature: Failed to record evaluation metric: #{e.class}: #{e}" }
          @telemetry.report(e, description: 'OpenFeature: Failed to record evaluation metric')
        end

        private

        # Counter is created lazily because OTel SDK may not be initialized
        # when the OpenFeature component is created.
        def get_or_create_counter
          @mutex.synchronize do
            return @counter if @counter
            return nil unless otel_metrics_enabled?

            ensure_meter_provider_initialized!
            meter_provider = ::OpenTelemetry.meter_provider
            return nil unless meter_provider_available?(meter_provider)

            meter = meter_provider.meter(METER_NAME)
            @counter = meter.create_counter(
              METRIC_NAME,
              unit: METRIC_UNIT,
              description: METRIC_DESCRIPTION
            )
          end
        rescue => e
          @logger.debug { "OpenFeature: Failed to create metrics counter: #{e.class}: #{e}" }
          nil
        end

        def otel_metrics_enabled?
          unless Datadog.configuration.opentelemetry.metrics.enabled
            @logger.debug { 'OpenFeature: OTel metrics not enabled (DD_METRICS_OTEL_ENABLED=false), flag evaluation metrics disabled' }
            return false
          end
          true
        end

        # Initialize the OTel meter provider if not already set up.
        # This ensures metrics work even if the OTel SDK hook mechanism didn't fire.
        def ensure_meter_provider_initialized!
          return if meter_provider_available?(::OpenTelemetry.meter_provider)

          @logger.debug { 'OpenFeature: Initializing OTel meter provider directly' }
          require 'opentelemetry-metrics-sdk'
          require 'datadog/opentelemetry/metrics'
          Datadog::OpenTelemetry::Metrics.initialize!(Datadog.send(:components))
        rescue LoadError, NameError => e
          @logger.debug { "OpenFeature: Failed to initialize OTel metrics: #{e.class}: #{e}" }
        end

        def meter_provider_available?(meter_provider)
          return false if meter_provider.nil?

          defined?(::OpenTelemetry::SDK::Metrics::MeterProvider) &&
            meter_provider.is_a?(::OpenTelemetry::SDK::Metrics::MeterProvider)
        end

        def build_attributes(flag_key, variant:, reason:, error_code:, allocation_key:)
          # Pre-compute reason string conversions once to avoid repeated allocations
          normalized_reason, reason_upcase = normalize_reason_with_upcase(reason)

          attrs = {
            ATTR_FLAG_KEY => flag_key,
            ATTR_VARIANT => variant || '',
            ATTR_REASON => normalized_reason,
          }

          if allocation_key && !allocation_key.empty? && !exclude_allocation_key?(reason_upcase)
            attrs[ATTR_ALLOCATION_KEY] = allocation_key
          end

          if error_code
            attrs[ATTR_ERROR_TYPE] = normalize_error_type(error_code)
          end

          attrs
        end

        def normalize_reason_with_upcase(reason)
          return ['unknown', nil] if reason.nil?

          reason_str = reason.to_s
          return ['unknown', nil] if reason_str.empty?

          reason_upcase = reason_str.upcase
          normalized = REASON_MAP[reason_upcase] || reason_str.downcase
          [normalized, reason_upcase]
        end

        def normalize_error_type(error_code)
          return 'general' if error_code.nil?

          error_str = error_code.to_s
          return 'general' if error_str.empty?

          ERROR_TYPE_MAP[error_str] || 'general'
        end

        def exclude_allocation_key?(reason_upcase)
          return true if reason_upcase.nil?

          EXCLUDE_ALLOCATION_KEY_REASONS.include?(reason_upcase)
        end
      end
    end
  end
end
