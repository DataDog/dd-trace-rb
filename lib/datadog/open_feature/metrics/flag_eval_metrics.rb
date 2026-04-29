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

        # Reasons that should not include allocation_key in metrics
        EXCLUDE_ALLOCATION_KEY_REASONS = %w[error default disabled].freeze

        def initialize(telemetry:, logger:)
          @telemetry = telemetry
          @logger = logger
          @enabled = Datadog.configuration.opentelemetry.metrics.enabled
          @counter = nil
          @mutex = Mutex.new

          unless @enabled
            @logger.debug { 'OpenFeature: OTel metrics not enabled (DD_METRICS_OTEL_ENABLED=false), flag evaluation metrics disabled' }
          end
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
          return nil unless @enabled

          @mutex.synchronize do
            return @counter if @counter

            meter_provider = fetch_meter_provider
            return unless meter_provider

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

        # Fetch an available OTel meter provider, initializing if needed.
        # Returns the meter provider if available, nil otherwise.
        def fetch_meter_provider
          meter_provider = defined?(::OpenTelemetry) ? ::OpenTelemetry.meter_provider : nil
          return meter_provider if meter_provider_available?(meter_provider)

          @logger.debug { 'OpenFeature: Initializing OTel meter provider directly' }
          require 'opentelemetry-metrics-sdk'
          require 'datadog/opentelemetry/metrics'
          Datadog::OpenTelemetry::Metrics.initialize!(Datadog.send(:components))

          meter_provider = ::OpenTelemetry.meter_provider
          meter_provider_available?(meter_provider) ? meter_provider : nil
        rescue LoadError => e
          @logger.debug { "OpenFeature: Failed to initialize OTel metrics: #{e.class}: #{e}" }
          nil
        end

        def meter_provider_available?(meter_provider)
          return false if meter_provider.nil?
          return false unless defined?(::OpenTelemetry::SDK::Metrics::MeterProvider)

          meter_provider.is_a?(::OpenTelemetry::SDK::Metrics::MeterProvider)
        end

        def build_attributes(flag_key, variant:, reason:, error_code:, allocation_key:)
          reason_downcase = normalize_reason(reason)

          attrs = {
            ATTR_FLAG_KEY => flag_key,
            ATTR_VARIANT => variant.to_s,
            ATTR_REASON => reason_downcase,
          }

          if allocation_key && !allocation_key.empty? && !exclude_allocation_key?(reason_downcase)
            attrs[ATTR_ALLOCATION_KEY] = allocation_key
          end

          if error_code
            attrs[ATTR_ERROR_TYPE] = normalize_error_type(error_code)
          end

          attrs
        end

        def normalize_reason(reason)
          reason_str = reason.to_s
          reason_str.empty? ? 'unknown' : reason_str.downcase
        end

        def normalize_error_type(error_code)
          ERROR_TYPE_MAP.fetch(error_code.to_s, 'general')
        end

        def exclude_allocation_key?(reason_downcase)
          EXCLUDE_ALLOCATION_KEY_REASONS.include?(reason_downcase)
        end
      end
    end
  end
end
