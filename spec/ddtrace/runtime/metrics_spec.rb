# encoding: utf-8

require 'spec_helper'
require 'ddtrace'
require 'ddtrace/runtime/metrics'

RSpec.describe Datadog::Runtime::Metrics do
  subject(:runtime_metrics) { described_class.new }

  describe '#associate_with_span' do
    subject(:associate_with_span) { runtime_metrics.associate_with_span(span) }
    let(:span) { instance_double(Datadog::Span, service: service) }
    let(:service) { 'parser' }

    before do
      expect(span).to receive(:set_tag)
        .with(Datadog::Ext::Runtime::TAG_LANG, Datadog::Runtime::Identity.lang)

      associate_with_span
    end

    it 'registers the span\'s service' do
      expect(runtime_metrics.default_metric_options[:tags]).to include("service:#{service}")
    end
  end

  describe '#flush' do
    subject(:flush) { runtime_metrics.flush }

    shared_examples_for 'runtime metric flush' do |metric, metric_name|
      let(:metric_value) { double('metric_value') }

      context 'when available' do
        before(:each) { allow(runtime_metrics).to receive(:gauge) }

        it do
          allow(metric).to receive(:available?)
            .and_return(true)
          allow(metric).to receive(:value)
            .and_return(metric_value)

          flush

          expect(runtime_metrics).to have_received(:gauge)
            .with(metric_name, metric_value)
            .once
        end
      end

      context 'when unavailable' do
        it do
          allow(metric).to receive(:available?)
            .and_return(false)
          expect(metric).to_not receive(:value)
          expect(runtime_metrics).to_not receive(:gauge)
            .with(metric_name, anything)

          flush
        end
      end

      context 'when an error is thrown' do
        before(:each) { allow(Datadog::Logger.log).to receive(:error) }

        it do
          allow(metric).to receive(:available?)
            .and_raise(RuntimeError)

          flush

          expect(Datadog::Logger.log).to have_received(:error)
            .with(/Error while sending runtime metric./)
            .at_least(:once)
        end
      end
    end

    shared_examples_for 'a flush of all runtime metrics' do
      context 'including ClassCount' do
        it_behaves_like 'runtime metric flush',
                        Datadog::Runtime::ClassCount,
                        Datadog::Ext::Runtime::Metrics::METRIC_CLASS_COUNT
      end

      context 'including ThreadCount' do
        it_behaves_like 'runtime metric flush',
                        Datadog::Runtime::ThreadCount,
                        Datadog::Ext::Runtime::Metrics::METRIC_THREAD_COUNT
      end

      context 'including GC stats' do
        before(:each) { allow(runtime_metrics).to receive(:gauge) }

        it do
          flush

          runtime_metrics.gc_metrics.each do |metric_name, _metric_value|
            expect(runtime_metrics).to have_received(:gauge)
              .with(metric_name, kind_of(Numeric))
              .once
          end
        end
      end
    end

    it_behaves_like 'a flush of all runtime metrics'
  end

  describe '#gc_metrics' do
    subject(:gc_metrics) { runtime_metrics.gc_metrics }

    it 'has a metric for each value in GC.stat' do
      is_expected.to have(GC.stat.keys.count).items

      gc_metrics.each do |metric, value|
        expect(metric).to start_with(Datadog::Ext::Runtime::Metrics::METRIC_GC_PREFIX)
        expect(value).to be_a_kind_of(Numeric)
      end
    end
  end

  describe '#default_metric_options' do
    subject(:default_metric_options) { runtime_metrics.default_metric_options }

    describe ':tags' do
      subject(:default_tags) { default_metric_options[:tags] }

      context 'when no services have been registered' do
        it do
          is_expected.to include(*Datadog::Metrics.default_metric_options[:tags])
          is_expected.to include('language:ruby')
        end
      end

      context 'when services have been registered' do
        let(:services) { %w[parser serializer] }
        before(:each) { services.each { |service| runtime_metrics.register_service(service) } }

        it do
          is_expected.to include(*Datadog::Metrics.default_metric_options[:tags])
          is_expected.to include('language:ruby')
          is_expected.to include(*services.collect { |service| "service:#{service}" })
        end
      end
    end
  end
end
