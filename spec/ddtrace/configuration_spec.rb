require 'spec_helper'

require 'datadog/statsd'
require 'ddtrace/patcher'
require 'ddtrace/configuration'

RSpec.describe Datadog::Configuration do
  context 'when extended by a class' do
    subject(:test_class) { stub_const('TestClass', Class.new { extend Datadog::Configuration }) }

    describe '#configure' do
      subject(:configure) { test_class.configure }

      context 'when debug mode' do
        it 'is toggled with default settings' do
          # Assert initial state
          expect(test_class.logger.level).to be ::Logger::WARN

          # Enable
          test_class.configure do |c|
            c.diagnostics.debug = true
          end

          # Assert state change
          expect(test_class.logger.level).to be ::Logger::DEBUG

          # Disable
          test_class.configure do |c|
            c.diagnostics.debug = false
          end

          # Assert final state
          expect(test_class.logger.level).to be ::Logger::WARN
        end

        context 'is disabled with a custom logger in use' do
          let(:initial_log_level) { ::Logger::INFO }
          let(:logger) do
            ::Logger.new(StringIO.new).tap do |l|
              l.level = initial_log_level
            end
          end

          before do
            test_class.configure do |c|
              c.logger = logger
              c.diagnostics.debug = false
            end
          end

          it { expect(logger.level).to be initial_log_level }
        end
      end

      context 'when the logger' do
        context 'is replaced' do
          let(:old_logger) { Datadog::Logger.new(STDOUT) }
          let(:new_logger) { Datadog::Logger.new(STDOUT) }

          before do
            # Expect old loggers to NOT be closed, as closing
            # underlying streams can cause problems.
            expect(old_logger).to_not receive(:close)

            test_class.configure { |c| c.logger = old_logger }
            test_class.configure { |c| c.logger = new_logger }
          end

          it 'replaces the old logger' do
            expect(test_class.logger).to be new_logger
          end
        end

        context 'is reused' do
          let(:logger) { Datadog::Logger.new(STDOUT) }

          before do
            expect(logger).to_not receive(:close)

            test_class.configure { |c| c.logger = logger }
            test_class.configure { |c| c.logger = logger }
          end

          it 'reuses the same logger' do
            expect(test_class.logger).to be logger
          end
        end

        context 'is not changed' do
          let(:logger) { Datadog::Logger.new(STDOUT) }

          before do
            expect(logger).to_not receive(:close)

            test_class.configure { |c| c.logger = logger }
            test_class.configure { |_c| }
          end

          it 'reuses the same logger' do
            expect(test_class.logger).to be logger
          end
        end
      end

      context 'when the metrics' do
        context 'are replaced' do
          let(:old_statsd) { instance_double(Datadog::Statsd) }
          let(:new_statsd) { instance_double(Datadog::Statsd) }

          before do
            expect(old_statsd).to receive(:close).once

            test_class.configure do |c|
              c.runtime_metrics.statsd = old_statsd
              c.diagnostics.health_metrics.statsd = old_statsd
            end

            test_class.configure do |c|
              c.runtime_metrics.statsd = new_statsd
              c.diagnostics.health_metrics.statsd = new_statsd
            end
          end

          it 'replaces the old Statsd and closes it' do
            expect(test_class.runtime_metrics.metrics.statsd).to be new_statsd
            expect(test_class.health_metrics.statsd).to be new_statsd
          end
        end

        context 'have one of a few replaced' do
          let(:old_statsd) { instance_double(Datadog::Statsd) }
          let(:new_statsd) { instance_double(Datadog::Statsd) }

          before do
            # Since its being reused, it should not be closed.
            expect(old_statsd).to_not receive(:close)

            test_class.configure do |c|
              c.runtime_metrics.statsd = old_statsd
              c.diagnostics.health_metrics.statsd = old_statsd
            end

            test_class.configure do |c|
              c.runtime_metrics.statsd = new_statsd
            end
          end

          it 'uses new and old Statsd but does not close the old Statsd' do
            expect(test_class.runtime_metrics.metrics.statsd).to be new_statsd
            expect(test_class.health_metrics.statsd).to be old_statsd
          end
        end

        context 'are reused' do
          let(:statsd) { instance_double(Datadog::Statsd) }

          before do
            expect(statsd).to_not receive(:close)

            test_class.configure do |c|
              c.runtime_metrics.statsd = statsd
              c.diagnostics.health_metrics.statsd = statsd
            end

            test_class.configure do |c|
              c.runtime_metrics.statsd = statsd
              c.diagnostics.health_metrics.statsd = statsd
            end
          end

          it 'reuses the same Statsd' do
            expect(test_class.runtime_metrics.metrics.statsd).to be statsd
          end
        end

        context 'are not changed' do
          let(:statsd) { instance_double(Datadog::Statsd) }

          before do
            expect(statsd).to_not receive(:close)

            test_class.configure do |c|
              c.runtime_metrics.statsd = statsd
              c.diagnostics.health_metrics.statsd = statsd
            end

            test_class.configure { |_c| }
          end

          it 'reuses the same Statsd' do
            expect(test_class.runtime_metrics.metrics.statsd).to be statsd
          end
        end
      end

      context 'when the tracer' do
        context 'is replaced' do
          let(:old_tracer) { Datadog::Tracer.new }
          let(:new_tracer) { Datadog::Tracer.new }

          before do
            expect(old_tracer).to receive(:shutdown!)

            test_class.configure { |c| c.tracer = old_tracer }
            test_class.configure { |c| c.tracer = new_tracer }
          end

          it 'replaces the old tracer and shuts it down' do
            expect(test_class.tracer).to be new_tracer
          end
        end

        context 'is reused' do
          let(:tracer) { Datadog::Tracer.new }

          before do
            expect(tracer).to_not receive(:shutdown!)

            test_class.configure { |c| c.tracer = tracer }
            test_class.configure { |c| c.tracer = tracer }
          end

          it 'reuses the same tracer' do
            expect(test_class.tracer).to be tracer
          end
        end

        context 'is not changed' do
          let(:tracer) { Datadog::Tracer.new }

          before do
            expect(tracer).to_not receive(:shutdown!)

            test_class.configure { |c| c.tracer = tracer }
            test_class.configure { |_c| }
          end

          it 'reuses the same tracer' do
            expect(test_class.tracer).to be tracer
          end
        end
      end

      context 'when reconfigured multiple times' do
        context 'with runtime metrics active' do
          before do
            test_class.configure do |c|
              c.runtime_metrics.enabled = true
            end

            @old_runtime_metrics = test_class.runtime_metrics

            test_class.configure do |c|
              c.runtime_metrics.enabled = true
            end
          end

          it 'deactivates the old runtime metrics worker' do
            expect(@old_runtime_metrics.enabled?).to be false
            expect(@old_runtime_metrics.running?).to be false

            expect(test_class.runtime_metrics).to_not be @old_runtime_metrics

            expect(test_class.runtime_metrics.enabled?).to be true
            expect(test_class.runtime_metrics.running?).to be false
          end
        end
      end
    end

    describe '#health_metrics' do
      subject(:health_metrics) { test_class.health_metrics }
      it { is_expected.to be_a_kind_of(Datadog::Diagnostics::Health::Metrics) }
    end

    describe '#logger' do
      subject(:logger) { test_class.logger }
      it { is_expected.to be_a_kind_of(Datadog::Logger) }
      it { expect(logger.level).to be ::Logger::WARN }
    end

    describe '#runtime_metrics' do
      subject(:runtime_metrics) { test_class.runtime_metrics }
      it { is_expected.to be_a_kind_of(Datadog::Workers::RuntimeMetrics) }
      it { expect(runtime_metrics.enabled?).to be false }
      it { expect(runtime_metrics.running?).to be false }
    end

    describe '#tracer' do
      subject(:tracer) { test_class.tracer }
      it { is_expected.to be_a_kind_of(Datadog::Tracer) }
      it { expect(tracer.context_flush).to be_a_kind_of(Datadog::ContextFlush::Finished) }
    end
  end
end
