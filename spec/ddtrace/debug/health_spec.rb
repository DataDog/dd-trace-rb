# encoding: utf-8

require 'spec_helper'
require 'ddtrace'
require 'ddtrace/debug/health'

RSpec.describe Datadog::Debug::Health::Metrics do
  subject(:health_metrics) { described_class.new }

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

  # rubocop:disable Metrics/LineLength
  it_behaves_like 'a health metric', :distribution, :api_errors, Datadog::Ext::Debug::Health::Metrics::METRIC_API_ERRORS
  it_behaves_like 'a health metric', :distribution, :api_requests, Datadog::Ext::Debug::Health::Metrics::METRIC_API_REQUESTS
  it_behaves_like 'a health metric', :distribution, :api_responses, Datadog::Ext::Debug::Health::Metrics::METRIC_API_RESPONSES
  it_behaves_like 'a health metric', :distribution, :queue_accepted, Datadog::Ext::Debug::Health::Metrics::METRIC_QUEUE_ACCEPTED
  it_behaves_like 'a health metric', :distribution, :queue_accepted_lengths, Datadog::Ext::Debug::Health::Metrics::METRIC_QUEUE_ACCEPTED_LENGTHS
  it_behaves_like 'a health metric', :distribution, :queue_accepted_size, Datadog::Ext::Debug::Health::Metrics::METRIC_QUEUE_ACCEPTED_SIZE
  it_behaves_like 'a health metric', :distribution, :queue_dropped, Datadog::Ext::Debug::Health::Metrics::METRIC_QUEUE_DROPPED
  it_behaves_like 'a health metric', :gauge, :queue_length, Datadog::Ext::Debug::Health::Metrics::METRIC_QUEUE_LENGTH
  it_behaves_like 'a health metric', :gauge, :queue_max_length, Datadog::Ext::Debug::Health::Metrics::METRIC_QUEUE_MAX_LENGTH
  it_behaves_like 'a health metric', :gauge, :queue_size, Datadog::Ext::Debug::Health::Metrics::METRIC_QUEUE_SIZE
  it_behaves_like 'a health metric', :gauge, :queue_spans, Datadog::Ext::Debug::Health::Metrics::METRIC_QUEUE_SPANS
  it_behaves_like 'a health metric', :distribution, :traces_filtered, Datadog::Ext::Debug::Health::Metrics::METRIC_TRACES_FILTERED
  it_behaves_like 'a health metric', :distribution, :writer_cpu_time, Datadog::Ext::Debug::Health::Metrics::METRIC_WRITER_CPU_TIME
end
