require 'spec_helper'

require 'datadog/statsd'
require 'ddtrace/patcher'
require 'ddtrace/configuration'

RSpec.describe Datadog::Configuration do
  let(:default_log_level) { ::Logger::INFO }

  context 'when extended by a class' do
    subject(:test_class) { stub_const('TestClass', Class.new { extend Datadog::Configuration }) }

    describe '#configure' do
      subject(:configure) { test_class.configure }

      context 'when Settings are configured' do
        before do
          allow(Datadog::Configuration::Components).to receive(:new)
            .and_wrap_original do |m, *args|
            new_components = m.call(*args)
            allow(new_components).to receive(:shutdown!)
            allow(new_components).to receive(:startup!)
            new_components
          end
        end

        context 'and components have been initialized' do
          before do
            @original_components = test_class.send(:components)
          end

          it do
            # Components should have changed
            expect { configure }
              .to change { test_class.send(:components) }
              .from(@original_components)

            new_components = test_class.send(:components)
            expect(new_components).to_not be(@original_components)

            # Old components should shutdown, new components should startup
            expect(@original_components)
              .to have_received(:shutdown!)
              .with(new_components)
              .ordered

            expect(new_components)
              .to have_received(:startup!)
              .with(test_class.configuration)
              .ordered

            expect(new_components).to_not have_received(:shutdown!)
          end
        end

        context 'and components have not been initialized' do
          it do
            expect_any_instance_of(Datadog::Configuration::Components)
              .to_not receive(:shutdown!)

            configure

            # Components should have changed
            new_components = test_class.send(:components)

            # New components should startup
            expect(new_components)
              .to have_received(:startup!)
              .with(test_class.configuration)

            expect(new_components).to_not have_received(:shutdown!)
          end
        end
      end

      context 'when an object is configured' do
        subject(:configure) { test_class.configure(object, options) }

        let(:object) { double('object') }
        let(:options) { {} }

        let(:pin_setup) { instance_double(Datadog::Configuration::PinSetup) }

        it 'attaches a pin to the object' do
          expect(Datadog::Configuration::PinSetup)
            .to receive(:new)
            .with(object, options)
            .and_return(pin_setup)

          expect(pin_setup).to receive(:call)

          configure
        end
      end

      context 'when debug mode' do
        it 'is toggled with default settings' do
          # Assert initial state
          expect(test_class.logger.level).to be default_log_level

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
          expect(test_class.logger.level).to be default_log_level
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
          let(:old_logger) { Datadog::Logger.new($stdout) }
          let(:new_logger) { Datadog::Logger.new($stdout) }

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
          let(:logger) { Datadog::Logger.new($stdout) }

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
          let(:logger) { Datadog::Logger.new($stdout) }

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

      context 'when the profiler' do
        context 'is not changed' do
          before { skip 'Profiling is not supported.' unless Datadog::Profiling.supported? }

          context 'and profiling is enabled' do
            before do
              allow(test_class.configuration.profiling)
                .to receive(:enabled)
                .and_return(true)

              allow_any_instance_of(Datadog::Profiler)
                .to receive(:start)
              allow_any_instance_of(Datadog::Profiling::Tasks::Setup)
                .to receive(:run)
            end

            it 'starts the profiler' do
              configure
              expect(test_class.profiler).to have_received(:start)
            end
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

          it 'stops the old runtime metrics worker' do
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
      it { expect(logger.level).to be default_log_level }

      context 'when components are not initialized' do
        it 'does not cause them to be initialized' do
          logger

          expect(test_class.send(:components?)).to be false
        end
      end

      context 'when components are being replaced' do
        before do
          test_class.configure
          allow(test_class.send(:components)).to receive(:shutdown!)
        end

        it 'returns the old logger' do
          old_logger = test_class.logger
          logger_during_component_replacement = nil

          allow(Datadog::Configuration::Components).to receive(:new) do
            # simulate getting the logger during reinitialization
            logger_during_component_replacement = test_class.logger
            instance_double(Datadog::Configuration::Components, startup!: nil)
          end

          test_class.configure

          expect(logger_during_component_replacement).to be old_logger
        end
      end
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

    describe '#shutdown!' do
      subject(:shutdown!) { test_class.shutdown! }

      let!(:original_components) { test_class.send(:components) }

      it 'gracefully shuts down components' do
        expect(original_components).to receive(:shutdown!)

        shutdown!
      end

      it 'does not attempt to recreate components' do
        shutdown!

        expect(test_class.send(:components)).to be(original_components)
      end
    end

    describe '#reset!' do
      subject(:reset!) { test_class.send(:reset!) }

      let!(:original_components) { test_class.send(:components) }

      it 'gracefully shuts down components' do
        expect(original_components).to receive(:shutdown!)

        reset!
      end

      it 'allows for component re-creation' do
        reset!

        expect(test_class.send(:components)).to_not be(original_components)
      end

      context 'with configuration values set' do
        let(:default_value) { 100 }
        let(:custom_value) { 777 }

        before do
          test_class.configuration.sampling.rate_limit = custom_value
        end

        it 'resets the configuration' do
          expect { reset! }.to change { test_class.configuration.sampling.rate_limit }
            .from(custom_value).to(default_value)
        end
      end
    end

    describe '#components' do
      context 'when components are not initialized' do
        it 'initializes the components' do
          test_class.send(:components)

          expect(test_class.send(:components?)).to be true
        end

        context 'when allow_initialization is false' do
          it 'does not initialize the components' do
            test_class.send(:components, allow_initialization: false)

            expect(test_class.send(:components?)).to be false
          end
        end
      end

      context 'when components are initialized' do
        before { test_class.send(:components) }

        after { described_class.const_get(:COMPONENTS_WRITE_LOCK).tap { |lock| lock.unlock if lock.owned? } }

        it 'returns the components without touching the COMPONENTS_WRITE_LOCK' do
          described_class.const_get(:COMPONENTS_WRITE_LOCK).lock

          expect(test_class.send(:components)).to_not be_nil
        end
      end
    end

    describe '#safely_synchronize' do
      it 'runs the given block while holding the COMPONENTS_WRITE_LOCK' do
        block_ran = false

        test_class.send(:safely_synchronize) do
          block_ran = true
          expect(described_class.const_get(:COMPONENTS_WRITE_LOCK)).to be_owned
        end

        expect(block_ran).to be true
      end

      it 'returns the value of the given block' do
        expect(test_class.send(:safely_synchronize) { :returned_value }).to be :returned_value
      end

      it 'provides a write_components callback that can be used to update the components' do
        test_class.send(:safely_synchronize) do |write_components|
          write_components.call(:updated_components)
        end

        expect(test_class.send(:components)).to be :updated_components
      end

      context 'when recursive execution triggers a deadlock' do
        subject(:safely_synchronize) { test_class.send(:safely_synchronize) { test_class.send(:safely_synchronize) } }

        before do
          allow(test_class.send(:logger_without_components)).to receive(:error)
        end

        it 'logs an error' do
          expect(test_class.send(:logger_without_components)).to receive(:error).with(/Detected deadlock/)

          safely_synchronize
        end

        it 'does not let the exception propagate' do
          expect { safely_synchronize }.to_not raise_error
        end

        it 'returns nil' do
          expect(safely_synchronize).to be nil
        end
      end
    end
  end
end
