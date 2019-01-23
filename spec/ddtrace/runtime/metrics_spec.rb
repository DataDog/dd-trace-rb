# encoding: utf-8

require 'spec_helper'
require 'ddtrace'
require 'ddtrace/runtime/metrics'

RSpec.describe Datadog::Runtime::Metrics do
  describe '::flush' do
    let(:metrics) { spy(Datadog::Metrics) }

    shared_examples_for 'runtime metric flush' do |metric, metric_name|
      let(:metric_value) { double('metric_value') }

      context 'when available' do
        it do
          expect(metric).to receive(:available?)
            .and_return(true)
          expect(metric).to receive(:value)
            .and_return(metric_value)
          expect(metrics).to receive(:gauge)
            .with(metric_name, metric_value)

          flush
        end
      end

      context 'when unavailable' do
        it do
          expect(metric).to receive(:available?)
            .and_return(false)
          expect(metric).to_not receive(:value)
          expect(metrics).to_not receive(:gauge)
            .with(metric_name, anything)

          flush
        end
      end

      context 'when an error is thrown' do
        it do
          expect(metric).to receive(:available?)
            .and_raise(RuntimeError)
          expect(Datadog::Tracer.log).to receive(:error)
            .with(/Error while sending runtime metric./)

          flush
        end
      end
    end

    shared_examples_for 'a flush of all runtime metrics' do
      context 'including ClassCount' do
        it_behaves_like 'runtime metric flush',
                        Datadog::Runtime::ClassCount,
                        Datadog::Ext::Runtime::METRIC_CLASS_COUNT
      end

      context 'including HeapSize' do
        it_behaves_like 'runtime metric flush',
                        Datadog::Runtime::HeapSize,
                        Datadog::Ext::Runtime::METRIC_HEAP_SIZE
      end

      context 'including ThreadCount' do
        it_behaves_like 'runtime metric flush',
                        Datadog::Runtime::ThreadCount,
                        Datadog::Ext::Runtime::METRIC_THREAD_COUNT
      end
    end

    context 'given no arguments' do
      subject(:flush) { described_class.flush }

      it_behaves_like 'a flush of all runtime metrics' do
        before(:each) { allow(Datadog).to receive(:metrics).and_return(metrics) }
      end
    end

    context 'given a Datadog::Metrics object' do
      subject(:flush) { described_class.flush(metrics) }
      it_behaves_like 'a flush of all runtime metrics'
    end
  end
end
