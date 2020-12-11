require 'spec_helper'

require 'datadog/statsd'
require 'ddtrace/configuration/components'

RSpec.describe Datadog::Configuration::Components do
  subject(:components) { described_class.new(settings) }
  let(:settings) { Datadog::Configuration::Settings.new }

  describe '::new' do
    let(:settings) { instance_double(Datadog::Configuration::Settings) }
    let(:logger) { instance_double(Datadog::Logger) }
    let(:tracer) { instance_double(Datadog::Tracer) }
    let(:runtime_metrics) { instance_double(Datadog::Workers::RuntimeMetrics) }
    let(:health_metrics) { instance_double(Datadog::Diagnostics::Health::Metrics) }

    before do
      expect(described_class).to receive(:build_logger)
        .with(settings)
        .and_return(logger)

      expect(described_class).to receive(:build_tracer)
        .with(settings)
        .and_return(tracer)

      expect(described_class).to receive(:build_runtime_metrics_worker)
        .with(settings)
        .and_return(runtime_metrics)

      expect(described_class).to receive(:build_health_metrics)
        .with(settings)
        .and_return(health_metrics)
    end

    it do
      expect(components.logger).to be logger
      expect(components.tracer).to be tracer
      expect(components.runtime_metrics).to be runtime_metrics
      expect(components.health_metrics).to be health_metrics
    end
  end

  describe '::build_health_metrics' do
    subject(:build_health_metrics) { described_class.build_health_metrics(settings) }

    context 'given settings' do
      shared_examples_for 'new health metrics' do
        let(:health_metrics) { instance_double(Datadog::Diagnostics::Health::Metrics) }
        let(:default_options) { { enabled: settings.diagnostics.health_metrics.enabled } }
        let(:options) { {} }

        before do
          expect(Datadog::Diagnostics::Health::Metrics).to receive(:new)
            .with(default_options.merge(options))
            .and_return(health_metrics)
        end

        it { is_expected.to be(health_metrics) }
      end

      context 'by default' do
        it_behaves_like 'new health metrics'
      end

      context 'with :enabled' do
        let(:enabled) { double('enabled') }

        before do
          allow(settings.diagnostics.health_metrics)
            .to receive(:enabled)
            .and_return(enabled)
        end

        it_behaves_like 'new health metrics' do
          let(:options) { { enabled: enabled } }
        end
      end

      context 'with :statsd' do
        let(:statsd) { instance_double(Datadog::Statsd) }

        before do
          allow(settings.diagnostics.health_metrics)
            .to receive(:statsd)
            .and_return(statsd)
        end

        it_behaves_like 'new health metrics' do
          let(:options) { { statsd: statsd } }
        end
      end
    end
  end

  describe '::build_logger' do
    subject(:build_logger) { described_class.build_logger(settings) }

    context 'given an instance' do
      let(:instance) { instance_double(Datadog::Logger) }

      before do
        expect(settings.logger).to receive(:instance)
          .and_return(instance)

        expect(instance).to receive(:level=)
          .with(settings.logger.level)
      end

      it 'uses the logger instance' do
        expect(Datadog::Logger).to_not receive(:new)
        is_expected.to be(instance)
      end
    end

    context 'given settings' do
      shared_examples_for 'new logger' do
        let(:logger) { instance_double(Datadog::Logger) }
        let(:level) { settings.logger.level }

        before do
          expect(Datadog::Logger).to receive(:new)
            .with(STDOUT)
            .and_return(logger)

          expect(logger).to receive(:level=).with(level)
        end

        it { is_expected.to be(logger) }
      end

      context 'by default' do
        it_behaves_like 'new logger'
      end

      context 'with :level' do
        let(:level) { double('level') }

        before do
          allow(settings.logger)
            .to receive(:level)
            .and_return(level)
        end
      end

      context 'with debug: true' do
        before { settings.diagnostics.debug = true }

        it_behaves_like 'new logger' do
          let(:level) { ::Logger::DEBUG }
        end

        context 'and a conflicting log level' do
          before do
            allow(settings.logger)
              .to receive(:level)
              .and_return(::Logger::INFO)
          end

          it_behaves_like 'new logger' do
            let(:level) { ::Logger::DEBUG }
          end
        end
      end
    end
  end

  describe '::build_runtime_metrics' do
    subject(:build_runtime_metrics) { described_class.build_runtime_metrics(settings) }

    context 'given settings' do
      shared_examples_for 'new runtime metrics' do
        let(:runtime_metrics) { instance_double(Datadog::Runtime::Metrics) }
        let(:default_options) { { enabled: settings.runtime_metrics.enabled } }
        let(:options) { {} }

        before do
          expect(Datadog::Runtime::Metrics).to receive(:new)
            .with(default_options.merge(options))
            .and_return(runtime_metrics)
        end

        it { is_expected.to be(runtime_metrics) }
      end

      context 'by default' do
        it_behaves_like 'new runtime metrics'
      end

      context 'with :enabled' do
        let(:enabled) { double('enabled') }

        before do
          allow(settings.runtime_metrics)
            .to receive(:enabled)
            .and_return(enabled)
        end

        it_behaves_like 'new runtime metrics' do
          let(:options) { { enabled: enabled } }
        end
      end

      context 'with :service' do
        let(:service) { double('service') }

        before do
          allow(settings)
            .to receive(:service)
            .and_return(service)
        end

        it_behaves_like 'new runtime metrics' do
          let(:options) { { services: [service] } }
        end
      end

      context 'with :statsd' do
        let(:statsd) { instance_double(::Datadog::Statsd) }

        before do
          allow(settings.runtime_metrics)
            .to receive(:statsd)
            .and_return(statsd)
        end

        it_behaves_like 'new runtime metrics' do
          let(:options) { { statsd: statsd } }
        end
      end
    end
  end

  describe '::build_runtime_metrics_worker' do
    subject(:build_runtime_metrics_worker) { described_class.build_runtime_metrics_worker(settings) }

    context 'given settings' do
      shared_examples_for 'new runtime metrics worker' do
        let(:runtime_metrics_worker) { instance_double(Datadog::Workers::RuntimeMetrics) }
        let(:runtime_metrics) { instance_double(Datadog::Runtime::Metrics) }
        let(:default_options) do
          {
            enabled: settings.runtime_metrics.enabled,
            metrics: runtime_metrics
          }
        end
        let(:options) { {} }

        before do
          allow(described_class).to receive(:build_runtime_metrics)
            .with(settings)
            .and_return(runtime_metrics)

          expect(Datadog::Workers::RuntimeMetrics).to receive(:new)
            .with(default_options.merge(options))
            .and_return(runtime_metrics_worker)
        end

        it { is_expected.to be(runtime_metrics_worker) }
      end

      context 'by default' do
        it_behaves_like 'new runtime metrics worker'
      end

      context 'with :enabled' do
        let(:enabled) { double('enabled') }

        before do
          allow(settings.runtime_metrics)
            .to receive(:enabled)
            .and_return(enabled)
        end

        it_behaves_like 'new runtime metrics worker' do
          let(:options) { { enabled: enabled } }
        end
      end

      context 'with :opts' do
        let(:opts) { { custom_option: :custom_value } }

        before do
          allow(settings.runtime_metrics)
            .to receive(:opts)
            .and_return(opts)
        end

        it_behaves_like 'new runtime metrics worker' do
          let(:options) { opts }
        end
      end
    end
  end

  describe '::build_tracer' do
    subject(:build_tracer) { described_class.build_tracer(settings) }

    context 'given an instance' do
      let(:instance) { instance_double(Datadog::Tracer) }

      before do
        expect(settings.tracer).to receive(:instance)
          .and_return(instance)
      end

      it 'uses the logger instance' do
        expect(Datadog::Tracer).to_not receive(:new)
        is_expected.to be(instance)
      end
    end

    context 'given settings' do
      shared_examples_for 'new tracer' do
        let(:tracer) { instance_double(Datadog::Tracer) }
        let(:default_options) do
          {
            default_service: settings.service,
            enabled: settings.tracer.enabled,
            partial_flush: settings.tracer.partial_flush.enabled,
            tags: settings.tags
          }
        end
        let(:options) { {} }

        let(:default_configure_options) do
          {
            partial_flush: settings.tracer.partial_flush.enabled,
            transport_options: settings.tracer.transport_options,
            writer_options: settings.tracer.writer_options
          }
        end
        let(:configure_options) { {} }

        before do
          expect(Datadog::Tracer).to receive(:new)
            .with(default_options.merge(options))
            .and_return(tracer)

          expect(tracer).to receive(:configure)
            .with(default_configure_options.merge(configure_options))
        end

        it { is_expected.to be(tracer) }
      end

      context 'by default' do
        it_behaves_like 'new tracer'
      end

      context 'with :enabled' do
        let(:enabled) { double('enabled') }

        before do
          allow(settings.tracer)
            .to receive(:enabled)
            .and_return(enabled)
        end

        it_behaves_like 'new tracer' do
          let(:options) { { enabled: enabled } }
        end
      end

      context 'with :env' do
        let(:env) { double('env') }

        before do
          allow(settings)
            .to receive(:env)
            .and_return(env)
        end

        it_behaves_like 'new tracer' do
          let(:options) { { tags: { 'env' => env } } }
        end
      end

      context 'with :hostname' do
        let(:hostname) { double('hostname') }

        before do
          allow(settings.tracer)
            .to receive(:hostname)
            .and_return(hostname)
        end

        it_behaves_like 'new tracer' do
          let(:configure_options) { { hostname: hostname } }
        end
      end

      context 'with :partial_flush :enabled' do
        let(:enabled) { double('enabled') }

        before do
          allow(settings.tracer.partial_flush)
            .to receive(:enabled)
            .and_return(enabled)
        end

        it_behaves_like 'new tracer' do
          let(:options) { { partial_flush: enabled } }
          let(:configure_options) { { partial_flush: enabled } }
        end
      end

      context 'with :partial_flush :min_spans_threshold' do
        let(:min_spans_threshold) { double('min_spans_threshold') }

        before do
          allow(settings.tracer.partial_flush)
            .to receive(:min_spans_threshold)
            .and_return(min_spans_threshold)
        end

        it_behaves_like 'new tracer' do
          let(:configure_options) { { min_spans_before_partial_flush: min_spans_threshold } }
        end
      end

      context 'with :port' do
        let(:port) { double('port') }

        before do
          allow(settings.tracer)
            .to receive(:port)
            .and_return(port)
        end

        it_behaves_like 'new tracer' do
          let(:configure_options) { { port: port } }
        end
      end

      context 'with :priority_sampling' do
        let(:priority_sampling) { double('priority_sampling') }

        before do
          allow(settings.tracer)
            .to receive(:priority_sampling)
            .and_return(priority_sampling)
        end

        it_behaves_like 'new tracer' do
          let(:configure_options) { { priority_sampling: priority_sampling } }
        end
      end

      context 'with :sampler' do
        let(:sampler) { instance_double(Datadog::Sampler) }

        before do
          allow(settings.tracer)
            .to receive(:sampler)
            .and_return(sampler)
        end

        it_behaves_like 'new tracer' do
          let(:configure_options) { { sampler: sampler } }
        end
      end

      context 'with :service' do
        let(:service) { double('service') }

        before do
          allow(settings)
            .to receive(:service)
            .and_return(service)
        end

        it_behaves_like 'new tracer' do
          let(:options) { { default_service: service } }
        end
      end

      context 'with :tags' do
        let(:tags) do
          {
            'env' => 'tag_env',
            'version' => 'tag_version'
          }
        end

        before do
          allow(settings)
            .to receive(:tags)
            .and_return(tags)
        end

        it_behaves_like 'new tracer' do
          let(:options) { { tags: tags } }
        end

        context 'with conflicting :env' do
          let(:env) { 'setting_env' }

          before do
            allow(settings)
              .to receive(:env)
              .and_return(env)
          end

          it_behaves_like 'new tracer' do
            let(:options) { { tags: tags.merge('env' => env) } }
          end
        end

        context 'with conflicting :version' do
          let(:version) { 'setting_version' }

          before do
            allow(settings)
              .to receive(:version)
              .and_return(version)
          end

          it_behaves_like 'new tracer' do
            let(:options) { { tags: tags.merge('version' => version) } }
          end
        end
      end

      context 'with :transport_options' do
        let(:transport_options) { { custom_option: :custom_value } }

        before do
          allow(settings.tracer)
            .to receive(:transport_options)
            .and_return(transport_options)
        end

        it_behaves_like 'new tracer' do
          let(:configure_options) { { transport_options: transport_options } }
        end
      end

      context 'with :version' do
        let(:version) { double('version') }

        before do
          allow(settings)
            .to receive(:version)
            .and_return(version)
        end

        it_behaves_like 'new tracer' do
          let(:options) { { tags: { 'version' => version } } }
        end
      end

      context 'with :writer' do
        let(:writer) { instance_double(Datadog::Writer) }

        before do
          allow(settings.tracer)
            .to receive(:writer)
            .and_return(writer)
        end

        it_behaves_like 'new tracer' do
          let(:default_configure_options) do
            {
              partial_flush: settings.tracer.partial_flush.enabled,
              transport_options: settings.tracer.transport_options,
              writer: writer
            }
          end
        end
      end

      context 'with :writer_options' do
        let(:writer_options) { { custom_option: :custom_value } }

        before do
          allow(settings.tracer)
            .to receive(:writer_options)
            .and_return(writer_options)
        end

        it_behaves_like 'new tracer' do
          let(:configure_options) { { writer_options: writer_options } }
        end

        context 'and :writer' do
          let(:writer) { double('writer') }

          before do
            allow(settings.tracer)
              .to receive(:writer)
              .and_return(writer)
          end

          it_behaves_like 'new tracer' do
            # Ignores the writer options in favor of the writer
            let(:default_configure_options) do
              {
                partial_flush: settings.tracer.partial_flush.enabled,
                transport_options: settings.tracer.transport_options,
                writer: writer
              }
            end
          end
        end
      end
    end
  end

  describe '#shutdown!' do
    subject(:shutdown!) { components.shutdown!(replacement) }

    context 'given no replacement' do
      let(:replacement) { nil }

      it 'shuts down all components' do
        expect(components.tracer).to receive(:shutdown!)
        expect(components.runtime_metrics).to receive(:enabled=)
          .with(false)
        expect(components.runtime_metrics).to receive(:stop)
          .with(true)
        expect(components.runtime_metrics.metrics.statsd).to receive(:close)
        expect(components.health_metrics.statsd).to receive(:close)

        shutdown!
      end
    end

    context 'given a replacement' do
      shared_context 'replacement' do
        let(:replacement) { instance_double(described_class) }
        let(:tracer) { instance_double(Datadog::Tracer) }
        let(:runtime_metrics_worker) { instance_double(Datadog::Workers::RuntimeMetrics, metrics: runtime_metrics) }
        let(:runtime_metrics) { instance_double(Datadog::Runtime::Metrics, statsd: statsd) }
        let(:health_metrics) { instance_double(Datadog::Diagnostics::Health::Metrics, statsd: statsd) }
        let(:statsd) { instance_double(::Datadog::Statsd) }

        before do
          allow(replacement).to receive(:tracer).and_return(tracer)
          allow(replacement).to receive(:runtime_metrics).and_return(runtime_metrics_worker)
          allow(replacement).to receive(:health_metrics).and_return(health_metrics)
        end
      end

      context 'when no components are reused' do
        include_context 'replacement'

        it 'shuts down all components' do
          expect(components.tracer).to receive(:shutdown!)
          expect(components.runtime_metrics).to receive(:enabled=)
            .with(false)
          expect(components.runtime_metrics).to receive(:stop)
            .with(true)
          expect(components.runtime_metrics.metrics.statsd).to receive(:close)
          expect(components.health_metrics.statsd).to receive(:close)

          shutdown!
        end

        context 'and Statsd is not initialized' do
          before do
            allow(components.runtime_metrics.metrics)
              .to receive(:statsd)
              .and_return(nil)
          end

          it 'shuts down all components' do
            expect(components.tracer).to receive(:shutdown!)
            expect(components.runtime_metrics).to receive(:enabled=)
              .with(false)
            expect(components.runtime_metrics).to receive(:stop)
              .with(true)
            expect(components.health_metrics.statsd).to receive(:close)

            shutdown!
          end
        end
      end

      context 'when the tracer is re-used' do
        include_context 'replacement' do
          let(:tracer) { components.tracer }
        end

        it 'shuts down all components but the tracer' do
          expect(components.tracer).to_not receive(:shutdown!)
          expect(components.runtime_metrics).to receive(:enabled=)
            .with(false)
          expect(components.runtime_metrics).to receive(:stop)
            .with(true)
          expect(components.runtime_metrics.metrics.statsd).to receive(:close)
          expect(components.health_metrics.statsd).to receive(:close)

          shutdown!
        end
      end

      context 'when one of Statsd instances are reused' do
        include_context 'replacement' do
          let(:runtime_metrics_worker) { components.runtime_metrics }
        end

        it 'shuts down all components but the tracer' do
          expect(components.tracer).to receive(:shutdown!)
          expect(components.runtime_metrics).to receive(:enabled=)
            .with(false)
          expect(components.runtime_metrics).to receive(:stop)
            .with(true)
          expect(components.runtime_metrics.metrics.statsd).to_not receive(:close)
          expect(components.health_metrics.statsd).to receive(:close)

          shutdown!
        end
      end

      context 'when both Statsd instances are reused' do
        include_context 'replacement' do
          let(:runtime_metrics_worker) { components.runtime_metrics }
          let(:health_metrics) { components.health_metrics }
        end

        it 'shuts down all components but the tracer' do
          expect(components.tracer).to receive(:shutdown!)
          expect(components.runtime_metrics).to receive(:enabled=)
            .with(false)
          expect(components.runtime_metrics).to receive(:stop)
            .with(true)
          expect(components.runtime_metrics.metrics.statsd).to_not receive(:close)
          expect(components.health_metrics.statsd).to_not receive(:close)

          shutdown!
        end
      end
    end
  end
end
