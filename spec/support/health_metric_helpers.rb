require 'support/metric_helpers'
require 'ddtrace'
require 'datadog/tracing/diagnostics/ext'

module HealthMetricHelpers
  include RSpec::Mocks::ArgumentMatchers

  METRICS = {
    api_errors: { type: :count, name: Datadog::Tracing::Diagnostics::Ext::Health::Metrics::METRIC_API_ERRORS },
    api_requests: { type: :count, name: Datadog::Tracing::Diagnostics::Ext::Health::Metrics::METRIC_API_REQUESTS },
    api_responses: { type: :count, name: Datadog::Tracing::Diagnostics::Ext::Health::Metrics::METRIC_API_RESPONSES },
    error_context_overflow: {
      type: :count, name: Datadog::Tracing::Diagnostics::Ext::Health::Metrics::METRIC_ERROR_CONTEXT_OVERFLOW
    },
    error_instrumentation_patch: {
      type: :count, name: Datadog::Tracing::Diagnostics::Ext::Health::Metrics::METRIC_ERROR_INSTRUMENTATION_PATCH
    },
    error_span_finish: {
      type: :count, name: Datadog::Tracing::Diagnostics::Ext::Health::Metrics::METRIC_ERROR_SPAN_FINISH
    },
    error_unfinished_spans: {
      type: :count, name: Datadog::Tracing::Diagnostics::Ext::Health::Metrics::METRIC_ERROR_UNFINISHED_SPANS
    },
    instrumentation_patched: {
      type: :count, name: Datadog::Tracing::Diagnostics::Ext::Health::Metrics::METRIC_INSTRUMENTATION_PATCHED
    },
    queue_accepted: { type: :count, name: Datadog::Tracing::Diagnostics::Ext::Health::Metrics::METRIC_QUEUE_ACCEPTED },
    queue_accepted_lengths: {
      type: :count, name: Datadog::Tracing::Diagnostics::Ext::Health::Metrics::METRIC_QUEUE_ACCEPTED_LENGTHS
    },
    queue_dropped: { type: :count, name: Datadog::Tracing::Diagnostics::Ext::Health::Metrics::METRIC_QUEUE_DROPPED },
    transport_trace_too_large: {
      type: :count,
      name: Datadog::Tracing::Diagnostics::Ext::Health::Metrics::METRIC_TRANSPORT_TRACE_TOO_LARGE
    },
    transport_chunked: {
      type: :count, name: Datadog::Tracing::Diagnostics::Ext::Health::Metrics::METRIC_TRANSPORT_CHUNKED
    },
    traces_filtered: { type: :count, name: Datadog::Tracing::Diagnostics::Ext::Health::Metrics::METRIC_TRACES_FILTERED },
    writer_cpu_time: { type: :count, name: Datadog::Tracing::Diagnostics::Ext::Health::Metrics::METRIC_WRITER_CPU_TIME },
    queue_length: { type: :gauge, name: Datadog::Tracing::Diagnostics::Ext::Health::Metrics::METRIC_QUEUE_LENGTH },
    queue_max_length: { type: :gauge, name: Datadog::Tracing::Diagnostics::Ext::Health::Metrics::METRIC_QUEUE_MAX_LENGTH },
    queue_spans: { type: :gauge, name: Datadog::Tracing::Diagnostics::Ext::Health::Metrics::METRIC_QUEUE_SPANS },
    sampling_service_cache_length: {
      type: :gauge, name: Datadog::Tracing::Diagnostics::Ext::Health::Metrics::METRIC_SAMPLING_SERVICE_CACHE_LENGTH
    }
  }.freeze

  shared_context 'health metrics' do
    include_context 'metrics'

    let(:health_metrics) { Datadog.health_metrics }
    before { METRICS.each_key { |metric| allow(health_metrics).to receive(metric) } }

    def have_received_lazy_health_metric(metric, *expected_args)
      have_received(metric) do |&block|
        expect(block).to_not be nil

        if expected_args.length == 1
          expect(block.call).to eq(expected_args.first)
        elsif !expected_args.empty?
          expect(block.call).to eq(expected_args)
        end
      end
    end

    METRICS.each_key do |metric|
      define_method(:"have_received_#{metric}") do |value = kind_of(Numeric), options = {}|
        options = metric_options(options)
        check_options!(options)
        have_received(metric).with(value, options)
      end

      define_method(:"have_received_lazy_#{metric}") do |*expected_args|
        options = metric_options(options)
        check_options!(options)
        have_received_lazy_health_metric(metric, *expected_args)
      end
    end
  end
end
