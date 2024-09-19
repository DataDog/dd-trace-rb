require 'spec_helper'

require 'benchmark'
require 'concurrent'

require 'datadog/core'
require 'datadog/tracing/buffer'
require 'spec/datadog/core/buffer/shared_examples'

RSpec.describe Datadog::Tracing::TraceBuffer do
  subject(:buffer_class) { described_class }

  context 'with CRuby' do
    before { skip unless PlatformHelpers.mri? }

    it { is_expected.to eq Datadog::Tracing::CRubyTraceBuffer }
  end

  context 'with JRuby' do
    before { skip unless PlatformHelpers.jruby? }

    it { is_expected.to eq Datadog::Tracing::ThreadSafeTraceBuffer }
  end
end

RSpec.shared_examples 'trace buffer' do
  include_context 'health metrics'

  subject(:buffer) { described_class.new(max_size) }

  let(:max_size) { 0 }

  def measure_traces_size(traces)
    traces.inject(ObjectSpaceHelper.estimate_bytesize(traces)) do |sum, trace|
      sum + measure_trace_size(trace)
    end
  end

  def measure_trace_size(trace)
    trace.inject(ObjectSpaceHelper.estimate_bytesize(trace)) do |sum, span|
      sum + ObjectSpaceHelper.estimate_bytesize(span)
    end
  end

  describe '#initialize' do
    it { is_expected.to be_a_kind_of(described_class) }
  end

  describe '#push' do
    subject(:push) { items.each { |t| buffer.push(t) } }

    let(:items_count) { max_size + 1 }
    let(:pop) { buffer.pop }

    context 'given a max size' do
      let(:max_size) { 3 }

      it 'records health metrics' do
        push

        accepted_spans = items.inject(0) { |sum, t| sum + t.length }

        # A trace will be dropped at random, except the trace
        # that triggered the overflow.
        dropped_traces = items.reject { |t| pop.include?(t) }

        expected_traces = items - dropped_traces
        net_spans = expected_traces.inject(0) { |sum, t| sum + t.length }

        # Calling #pop produces metrics:
        # Accept events for every #push, and one drop event for overflow
        expect(health_metrics).to have_received(:queue_accepted)
          .with(items.length)
        expect(health_metrics).to have_received(:queue_accepted_lengths)
          .with(accepted_spans)

        expect(health_metrics).to have_received(:queue_dropped)
          .with(dropped_traces.length)

        # Metrics for queue gauges.
        expect(health_metrics).to have_received(:queue_max_length)
          .with(max_size)
        expect(health_metrics).to have_received(:queue_spans)
          .with(net_spans)
        expect(health_metrics).to have_received(:queue_length)
          .with(max_size)
      end
    end
  end

  describe '#concat' do
    let(:output) { buffer.pop }

    context 'given no limit' do
      let(:items) { get_test_traces(4) }
      let(:max_size) { 0 }

      it 'retains all items' do
        buffer.concat(items)
        expect(output.length).to eq(4)
      end
    end

    context 'given a max size' do
      let(:items) { get_test_traces(max_size + 1) }
      let(:max_size) { 3 }

      it 'does not exceed it' do
        buffer.concat(items)

        expect(output.length).to eq(max_size)
        expect(output).to include(items.last)
      end
    end
  end

  describe '#pop' do
    subject(:pop) { buffer.pop }

    let(:traces) { get_test_traces(2) }

    before { traces.each { |t| buffer.push(t) } }

    it 'records health metrics' do
      pop

      expected_spans = traces.inject(0) { |sum, t| sum + t.length }

      # Calling #pop produces metrics:
      # Metrics for accept events and one drop event
      expect(health_metrics).to have_received(:queue_accepted)
        .with(traces.length)
      expect(health_metrics).to have_received(:queue_accepted_lengths)
        .with(expected_spans)

      expect(health_metrics).to have_received(:queue_dropped)
        .with(0)

      # Metrics for queue gauges.
      expect(health_metrics).to have_received(:queue_max_length)
        .with(max_size)
      expect(health_metrics).to have_received(:queue_spans)
        .with(expected_spans)
      expect(health_metrics).to have_received(:queue_length)
        .with(traces.length)
    end
  end
end

RSpec.describe Datadog::Tracing::ThreadSafeTraceBuffer do
  let(:items) { get_test_traces(items_count) }

  before do
    logger = double(Datadog::Core::Logger)
    allow(logger).to receive(:debug?).and_return true
    allow(logger).to receive(:debug)
    allow(logger).to receive(:info)
    allow(logger).to receive(:warn)
    allow(logger).to receive(:error)

    allow(Datadog).to receive(:logger).and_return(logger)
  end

  it_behaves_like 'trace buffer'
  it_behaves_like 'thread-safe buffer'
  it_behaves_like 'performance'
end

RSpec.describe Datadog::Tracing::CRubyTraceBuffer do
  before do
    skip unless PlatformHelpers.mri?

    logger = double(Datadog::Core::Logger)
    allow(logger).to receive(:debug?).and_return true
    allow(logger).to receive(:debug)
    allow(logger).to receive(:info)
    allow(logger).to receive(:warn)
    allow(logger).to receive(:error)

    allow(Datadog).to receive(:logger).and_return(logger)
  end

  let(:items) { get_test_traces(items_count) }

  it_behaves_like 'trace buffer'
  it_behaves_like 'thread-safe buffer'
  it_behaves_like 'performance'
end
