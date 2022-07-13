# typed: false

require 'spec_helper'
require 'ddtrace'
require 'datadog/core/diagnostics/health'
require 'datadog/statsd'

RSpec.describe Datadog::Core::Diagnostics::Health::Metrics do
  subject(:health_metrics) { described_class.new(service: service, statsd: statsd) }
  let(:service) { nil }
  let(:statsd) { instance_double(Datadog::Statsd) }

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
  it_behaves_like 'a health metric', :count, :api_errors, Datadog::Core::Diagnostics::Ext::Health::Metrics::METRIC_API_ERRORS
  it_behaves_like 'a health metric', :count, :api_requests, Datadog::Core::Diagnostics::Ext::Health::Metrics::METRIC_API_REQUESTS
  it_behaves_like 'a health metric', :count, :api_responses, Datadog::Core::Diagnostics::Ext::Health::Metrics::METRIC_API_RESPONSES
  it_behaves_like 'a health metric', :count, :error_context_overflow, Datadog::Core::Diagnostics::Ext::Health::Metrics::METRIC_ERROR_CONTEXT_OVERFLOW
  it_behaves_like 'a health metric', :count, :error_instrumentation_patch, Datadog::Core::Diagnostics::Ext::Health::Metrics::METRIC_ERROR_INSTRUMENTATION_PATCH
  it_behaves_like 'a health metric', :count, :error_span_finish, Datadog::Core::Diagnostics::Ext::Health::Metrics::METRIC_ERROR_SPAN_FINISH
  it_behaves_like 'a health metric', :count, :error_unfinished_spans, Datadog::Core::Diagnostics::Ext::Health::Metrics::METRIC_ERROR_UNFINISHED_SPANS
  it_behaves_like 'a health metric', :count, :instrumentation_patched, Datadog::Core::Diagnostics::Ext::Health::Metrics::METRIC_INSTRUMENTATION_PATCHED
  it_behaves_like 'a health metric', :count, :queue_accepted, Datadog::Core::Diagnostics::Ext::Health::Metrics::METRIC_QUEUE_ACCEPTED
  it_behaves_like 'a health metric', :count, :queue_accepted_lengths, Datadog::Core::Diagnostics::Ext::Health::Metrics::METRIC_QUEUE_ACCEPTED_LENGTHS
  it_behaves_like 'a health metric', :count, :queue_dropped, Datadog::Core::Diagnostics::Ext::Health::Metrics::METRIC_QUEUE_DROPPED
  it_behaves_like 'a health metric', :count, :traces_filtered, Datadog::Core::Diagnostics::Ext::Health::Metrics::METRIC_TRACES_FILTERED
  it_behaves_like 'a health metric', :count, :writer_cpu_time, Datadog::Core::Diagnostics::Ext::Health::Metrics::METRIC_WRITER_CPU_TIME

  it_behaves_like 'a health metric', :gauge, :queue_length, Datadog::Core::Diagnostics::Ext::Health::Metrics::METRIC_QUEUE_LENGTH
  it_behaves_like 'a health metric', :gauge, :queue_max_length, Datadog::Core::Diagnostics::Ext::Health::Metrics::METRIC_QUEUE_MAX_LENGTH
  it_behaves_like 'a health metric', :gauge, :queue_spans, Datadog::Core::Diagnostics::Ext::Health::Metrics::METRIC_QUEUE_SPANS
  it_behaves_like 'a health metric', :gauge, :sampling_service_cache_length, Datadog::Core::Diagnostics::Ext::Health::Metrics::METRIC_SAMPLING_SERVICE_CACHE_LENGTH
  # rubocop:enable Layout/LineLength

  describe '.new' do
    context 'with service' do
      let(:service) { 'srv' }

      it 'sets the statsd service tag' do
        expect(statsd).to receive(:count).with(any_args, tags: array_including('service:srv'))
        health_metrics.api_requests(1)
      end
    end

    context 'with no service' do
      let(:service) { nil }

      it 'does not set the statsd service tag' do
        expect(statsd).to_not receive(:count).with(any_args, tags: array_including(include('service:')))
        health_metrics.api_requests(1)
      end
    end
  end
end
