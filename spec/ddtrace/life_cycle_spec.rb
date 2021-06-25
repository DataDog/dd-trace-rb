require 'spec_helper'

# require 'datadog/statsd'
# require 'ddtrace/patcher'
require 'ddtrace/life_cycle'

# require 'ddtrace'

RSpec.describe Datadog::LifeCycle do
  context 'when extended by a class' do
    subject(:test_class) { stub_const('TestClass', Class.new { extend Datadog::LifeCycle }) }
    let(:runtime) { instance_double(Datadog::Tracing::Runtime) }

    before do
      allow(runtime).to receive(:startup!)
    end

    [
      :configuration,
      :configure,
      :health_metrics,
      :logger,
      :profiler,
      :runtime_metrics,
      :shutdown!,
      :tracer
    ]
    .each do |method_name|
      describe "##{method_name}" do
        before { test_class.send(:start!, runtime) }

        it "delegates to runtime.#{method_name}" do
          expect(runtime).to receive(method_name)

          test_class.public_send(method_name)
        end
      end
    end

    describe '#start!' do
      subject(:start!) { test_class.send(:start!) }

      context 'with default arguments' do
        it 'creates a new runtime' do
          expect(Datadog::Tracing::Runtime).to receive(:new).and_return(runtime)
          expect(runtime).to receive(:startup!)

          start!

          expect(test_class.send(:runtime)).to eq(runtime)
        end

        it 'initializes basic components before invoking @runtime.startup!' do
          logger = double('Logger')
          expect(runtime).to receive(:logger).and_return(logger)

          expect(Datadog::Tracing::Runtime).to receive(:new).and_return(runtime)

          expect(runtime).to receive(:startup!) do
            # Call logger from mock #startup!, mimicking
            # a real component logging during initialization.
            expect(test_class.logger).to be(logger)
          end

          start!
        end
      end

      context 'with a runtime argument' do
        it 'creates a new runtime' do
          expect(runtime).to receive(:startup!)

          test_class.send(:start!, runtime)

          expect(test_class.send(:runtime)).to eq(runtime)
        end
      end
    end
  end
end
