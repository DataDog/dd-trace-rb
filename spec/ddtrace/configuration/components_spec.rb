require 'spec_helper'

require 'ddtrace/configuration/components'

RSpec.describe Datadog::Configuration::Components do
  describe '::new' do
    subject(:components) { described_class.new(settings) }
    let(:settings) { Datadog::Configuration::Settings.new }

    context 'given debug' do
      context 'settings' do
        before { settings.diagnostics.debug = true }
        it { expect(components.logger.level).to eq(::Logger::DEBUG) }
      end
    end

    context 'given health metrics' do
      context 'settings' do
        let(:statsd) { instance_double('statsd') }

        before do
          settings.diagnostics.health_metrics.enabled = true
          settings.diagnostics.health_metrics.statsd = statsd
        end

        it { expect(components.health_metrics.enabled?).to be true }
        it { expect(components.health_metrics.statsd).to be statsd }
      end
    end

    context 'given logger' do
      context 'instance' do
        let(:logger) { Datadog::Logger.new(STDOUT) }
        before { settings.logger = logger }

        it 'uses the logger instance' do
          expect(components.logger).to be(logger)
        end

        context 'and debug mode is set' do
          before { settings.diagnostics.debug = true }

          it 'uses the logger instance with debug level' do
            expect(components.logger).to be(logger)
            expect(components.logger.level).to be(::Logger::DEBUG)
          end
        end
      end

      context 'settings' do
        let(:logger) { components.logger }

        before do
          settings.logger.level = ::Logger::INFO
        end

        it { expect(logger.level).to eq(::Logger::INFO) }

        context 'and debug mode enabled' do
          before { settings.diagnostics.debug = true }
          it { expect(logger.level).to eq(::Logger::DEBUG) }
        end
      end
    end

    context 'given runtime metrics' do
      context 'settings' do
        context 'in the old style' do
          context 'with #runtime_metrics_enabled=' do
            before { settings.runtime_metrics_enabled = true }
            it { expect(components.runtime_metrics.enabled?).to be true }
          end

          context 'with #runtime_metrics' do
            let(:statsd) { instance_double('statsd') }
            before { settings.runtime_metrics enabled: true, statsd: statsd }
            it { expect(components.runtime_metrics.enabled?).to be true }
            it { expect(components.runtime_metrics.statsd).to be statsd }
          end
        end

        context 'in the new style' do
          let(:statsd) { instance_double('statsd') }

          before do
            settings.runtime_metrics.enabled = true
            settings.runtime_metrics.statsd = statsd
          end

          it { expect(components.runtime_metrics.enabled?).to be true }
          it { expect(components.runtime_metrics.statsd).to be statsd }
        end
      end
    end

    context 'given tracer' do
      context 'instance' do
        let(:tracer) { instance_double(Datadog::Tracer, writer: writer) }
        let(:writer) { instance_double(Datadog::Writer, runtime_metrics: runtime_metrics) }
        let(:runtime_metrics) { instance_double(Datadog::Runtime::Metrics) }

        before do
          settings.tracer = tracer
          settings.service = 'my-service'
          settings.tags = { 'custom-tag' => 'custom-value' }

          # NOTE: When given a tracer instance, it is expected to be fully configured.
          #       Do not expect the other settings to mutate the tracer instance.
          expect(tracer).to_not receive(:configure)
          expect(tracer).to_not receive(:set_tags)
          allow(runtime_metrics).to receive(:configure)
        end

        it 'uses the tracer instance' do
          expect(components.tracer).to be(tracer)
        end
      end

      context 'settings' do
        before do
          settings.service = 'my-service'
          settings.env = 'test-env'
          settings.tags = { 'custom-tag' => 'custom-value' }
          settings.version = '0.1.0.alpha'
          settings.tracer.enabled = false
          settings.tracer.hostname = 'my-agent'
          settings.tracer.port = 1234
          settings.tracer.partial_flush.enabled = true
          settings.tracer.partial_flush.min_spans_threshold = 123
        end

        describe '#tracer' do
          subject(:tracer) { components.tracer }

          it { expect(tracer.enabled).to be false }
          it { expect(tracer.default_service).to eq('my-service') }
          it { expect(tracer.context_flush).to be_a_kind_of(Datadog::ContextFlush::Partial) }
          it { expect(tracer.context_flush.instance_variable_get(:@min_spans_for_partial)).to eq 123 }
          it { expect(tracer.writer.transport.current_api.adapter.hostname).to eq 'my-agent' }
          it { expect(tracer.writer.transport.current_api.adapter.port).to eq 1234 }

          it 'has tags applied' do
            expect(tracer.tags).to include(
              'env' => 'test-env',
              'custom-tag' => 'custom-value',
              'version' => '0.1.0.alpha'
            )
          end
        end

        context 'including :writer' do
          subject(:tracer) { components.tracer }
          let(:writer) { Datadog::Writer.new }

          before do
            settings.tracer.hostname = 'my-agent'
            settings.tracer.port = 1234
            settings.tracer.writer = writer
          end

          it { expect(tracer.writer).to be writer }

          # NOTE: Expect settings to NOT be retained because custom writer instances
          #       supersede these settings: declare settings in Writer::new instead.
          it { expect(tracer.writer.transport.current_api.adapter.hostname).to_not eq 'my-agent' }
          it { expect(tracer.writer.transport.current_api.adapter.port).to_not eq 1234 }
        end

        context 'including :writer_options' do
          subject(:tracer) { components.tracer }

          before do
            settings.tracer.writer_options = { buffer_size: 1234 }
          end

          it { expect(tracer.writer.instance_variable_get(:@buff_size)).to eq 1234 }
        end
      end
    end
  end
end
