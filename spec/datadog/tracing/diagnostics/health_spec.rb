require 'spec_helper'
require 'ddtrace'
require 'datadog/core/diagnostics/health'
require 'datadog/tracing/diagnostics/health'

RSpec.describe Datadog::Tracing::Diagnostics::Health::Metrics do
  # TODO: Core::Health::Metrics directly extends Tracing::Health::Metrics
  #       In the future, have tracing add this behavior itself. For now,
  #       just use the core metrics class to drive the tests.
  subject(:health_metrics) { Datadog::Core::Diagnostics::Health::Metrics.new }

  shared_examples_for 'a health metric' do |type, name, stat|
    subject(:health_metric) { health_metrics.send(name, *args, &block) }

    let(:args) { [1] }
    let(:block) { proc {} }

    it 'sends a measurement of the designated type' do
      expect(health_metrics).to receive(type) do |*received_args, &received_block|
        expect(received_args).to eq([stat, *args])
        expect(received_block).to be block
      end

      health_metric
    end
  end

  # rubocop:disable Layout/LineLength
  it_behaves_like 'a health metric', :count, :api_errors, Datadog::Tracing::Diagnostics::Ext::Health::Metrics::METRIC_API_ERRORS
  it_behaves_like 'a health metric', :count, :api_requests, Datadog::Tracing::Diagnostics::Ext::Health::Metrics::METRIC_API_REQUESTS
  it_behaves_like 'a health metric', :count, :api_responses, Datadog::Tracing::Diagnostics::Ext::Health::Metrics::METRIC_API_RESPONSES
  it_behaves_like 'a health metric', :count, :error_context_overflow, Datadog::Tracing::Diagnostics::Ext::Health::Metrics::METRIC_ERROR_CONTEXT_OVERFLOW
  it_behaves_like 'a health metric', :count, :error_instrumentation_patch, Datadog::Tracing::Diagnostics::Ext::Health::Metrics::METRIC_ERROR_INSTRUMENTATION_PATCH
  it_behaves_like 'a health metric', :count, :error_span_finish, Datadog::Tracing::Diagnostics::Ext::Health::Metrics::METRIC_ERROR_SPAN_FINISH
  it_behaves_like 'a health metric', :count, :error_unfinished_spans, Datadog::Tracing::Diagnostics::Ext::Health::Metrics::METRIC_ERROR_UNFINISHED_SPANS
  it_behaves_like 'a health metric', :count, :instrumentation_patched, Datadog::Tracing::Diagnostics::Ext::Health::Metrics::METRIC_INSTRUMENTATION_PATCHED
  it_behaves_like 'a health metric', :count, :queue_accepted, Datadog::Tracing::Diagnostics::Ext::Health::Metrics::METRIC_QUEUE_ACCEPTED
  it_behaves_like 'a health metric', :count, :queue_accepted_lengths, Datadog::Tracing::Diagnostics::Ext::Health::Metrics::METRIC_QUEUE_ACCEPTED_LENGTHS
  it_behaves_like 'a health metric', :count, :queue_dropped, Datadog::Tracing::Diagnostics::Ext::Health::Metrics::METRIC_QUEUE_DROPPED
  it_behaves_like 'a health metric', :count, :traces_filtered, Datadog::Tracing::Diagnostics::Ext::Health::Metrics::METRIC_TRACES_FILTERED
  it_behaves_like 'a health metric', :count, :writer_cpu_time, Datadog::Tracing::Diagnostics::Ext::Health::Metrics::METRIC_WRITER_CPU_TIME

  it_behaves_like 'a health metric', :gauge, :queue_length, Datadog::Tracing::Diagnostics::Ext::Health::Metrics::METRIC_QUEUE_LENGTH
  it_behaves_like 'a health metric', :gauge, :queue_max_length, Datadog::Tracing::Diagnostics::Ext::Health::Metrics::METRIC_QUEUE_MAX_LENGTH
  it_behaves_like 'a health metric', :gauge, :queue_spans, Datadog::Tracing::Diagnostics::Ext::Health::Metrics::METRIC_QUEUE_SPANS
  it_behaves_like 'a health metric', :gauge, :sampling_service_cache_length, Datadog::Tracing::Diagnostics::Ext::Health::Metrics::METRIC_SAMPLING_SERVICE_CACHE_LENGTH
  # rubocop:enable Layout/LineLength
end
