# typed: false
require 'spec_helper'
require 'ddtrace'
require 'ddtrace/runtime/metrics'

RSpec.describe Datadog::Runtime::Metrics do
  subject(:runtime_metrics) { described_class.new(**options) }

  let(:options) { {} }

  describe '::new' do
    context 'given :services' do
      let(:options) { super().merge(services: services) }
      let(:services) { %w[service-a service-b] }

      it do
        expect(runtime_metrics.send(:service_tags)).to include(
          "#{Datadog::Ext::Runtime::Metrics::TAG_SERVICE}:service-a",
          "#{Datadog::Ext::Runtime::Metrics::TAG_SERVICE}:service-b"
        )
      end
    end
  end

  describe '#associate_with_span' do
    subject(:associate_with_span) { runtime_metrics.associate_with_span(span) }

    let(:span) { Datadog::SpanOperation.new('dummy', service: service) }
    let(:service) { 'parser' }

    context 'when enabled' do
      before do
        runtime_metrics.enabled = true

        associate_with_span
      end

      context 'with internal span' do
        it 'registers the span\'s service' do
          expect(runtime_metrics.default_metric_options[:tags]).to include("service:#{service}")
          expect(span.get_tag(Datadog::Ext::Runtime::TAG_LANG)).to eq(Datadog::Core::Environment::Identity.lang)
        end
      end

      context 'with external resource span' do
        let(:span) do
          super().tap { |s| s.set_tag(Datadog::Ext::Integration::TAG_PEER_SERVICE, 'peer-service-name') }
        end

        it "doesn't tag as an internal language span" do
          expect(span.get_tag(Datadog::Ext::Runtime::TAG_LANG)).to be nil
        end
      end
    end

    context 'when disabled' do
      before do
        runtime_metrics.enabled = false
        expect(span).to_not receive(:set_tag)
        associate_with_span
      end

      it 'registers the span\'s service' do
        expect(runtime_metrics.default_metric_options[:tags]).to_not include("service:#{service}")
      end
    end
  end

  describe '#register_service' do
    subject(:register_service) { runtime_metrics.register_service(service) }

    let(:service) { 'parser' }

    context 'when enabled' do
      before do
        runtime_metrics.enabled = true
        register_service
      end

      it 'registers the span\'s service' do
        expect(runtime_metrics.default_metric_options[:tags]).to include("service:#{service}")
      end
    end

    context 'when disabled' do
      before do
        runtime_metrics.enabled = false
        register_service
      end

      it 'registers the span\'s service' do
        expect(runtime_metrics.default_metric_options[:tags]).to_not include("service:#{service}")
      end
    end
  end

  describe '#flush' do
    subject(:flush) { runtime_metrics.flush }

    shared_examples_for 'runtime metric flush' do |metric, metric_name|
      let(:metric_value) { double('metric_value') }

      context 'when available' do
        before { allow(runtime_metrics).to receive(:gauge) }

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
        before { allow(Datadog.logger).to receive(:error) }

        it do
          allow(metric).to receive(:available?)
            .and_raise(RuntimeError)

          flush

          expect(Datadog.logger).to have_received(:error)
            .with(/Error while sending runtime metric./)
            .at_least(:once)
        end
      end
    end

    shared_examples_for 'a flush of all runtime metrics' do
      context 'including ClassCount' do
        it_behaves_like 'runtime metric flush',
                        Datadog::Core::Environment::ClassCount,
                        Datadog::Ext::Runtime::Metrics::METRIC_CLASS_COUNT
      end

      context 'including ThreadCount' do
        it_behaves_like 'runtime metric flush',
                        Datadog::Core::Environment::ThreadCount,
                        Datadog::Ext::Runtime::Metrics::METRIC_THREAD_COUNT
      end

      context 'including GC stats' do
        before { allow(runtime_metrics).to receive(:gauge) }

        it do
          flush

          runtime_metrics.gc_metrics.each_key do |metric_name|
            expect(runtime_metrics).to have_received(:gauge)
              .with(metric_name, kind_of(Numeric))
              .once
          end
        end
      end

      context 'including VMCache stats' do
        before do
          skip('This feature is only supported in CRuby') unless PlatformHelpers.mri?

          allow(runtime_metrics).to receive(:gauge)
        end

        context 'with Ruby < 3', if: RUBY_VERSION < '3.0.0' do
          it 'records global cache counters' do
            flush

            expect(runtime_metrics).to have_received(:gauge)
              .with(Datadog::Ext::Runtime::Metrics::METRIC_GLOBAL_CONSTANT_STATE, kind_of(Numeric))
              .once

            expect(runtime_metrics).to have_received(:gauge)
              .with(Datadog::Ext::Runtime::Metrics::METRIC_GLOBAL_METHOD_STATE, kind_of(Numeric))
              .once
          end
        end

        context 'with Ruby >= 3', if: RUBY_VERSION >= '3.0.0' do
          it 'records constant cache counter' do
            flush

            expect(runtime_metrics).to have_received(:gauge)
              .with(Datadog::Ext::Runtime::Metrics::METRIC_GLOBAL_CONSTANT_STATE, kind_of(Numeric))
              .once
          end
        end
      end
    end

    it_behaves_like 'a flush of all runtime metrics'
  end

  describe '#gc_metrics' do
    subject(:gc_metrics) { runtime_metrics.gc_metrics }

    context 'on MRI' do
      before { skip unless PlatformHelpers.mri? }

      it 'has a metric for each value in GC.stat' do
        is_expected.to have(GC.stat.keys.size).items

        gc_metrics.each do |metric, value|
          expect(metric).to start_with(Datadog::Ext::Runtime::Metrics::METRIC_GC_PREFIX)
          expect(value).to be_a_kind_of(Numeric)
        end
      end
    end

    context 'on JRuby' do
      before { skip unless PlatformHelpers.jruby? }

      it 'has a metric for each value in GC.stat' do
        is_expected.to have_at_least(GC.stat.keys.count).items

        gc_metrics.each do |metric, value|
          expect(metric).to start_with(Datadog::Ext::Runtime::Metrics::METRIC_GC_PREFIX)
          expect(value).to be_a_kind_of(Numeric)
        end
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

        before { services.each { |service| runtime_metrics.register_service(service) } }

        it do
          is_expected.to include(*Datadog::Metrics.default_metric_options[:tags])
          is_expected.to include('language:ruby')
          is_expected.to include(*services.collect { |service| "service:#{service}" })
        end
      end
    end
  end
end
