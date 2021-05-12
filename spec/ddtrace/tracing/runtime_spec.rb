require 'ddtrace/tracing/runtime'

RSpec.describe Datadog::Tracing::Runtime do
  subject(:runtime) { described_class.new(configuration, components) }
  let(:configuration) { instance_double(Datadog::Configuration::Settings) }
  let(:components) { instance_double(Datadog::Configuration::Components) }

  context '#initialize' do
    context 'with default arguments' do
      subject(:runtime) { described_class.new }

      it 'initializes configuration and components' do
        expect(Datadog::Configuration::Settings).to receive(:new).and_return(configuration)
        expect(Datadog::Configuration::Components).to receive(:new).with(configuration).and_return(components)

        expect(runtime.configuration).to be(configuration)
        expect(runtime.send(:components)).to be(components)
      end
    end

    it 'stores configuration and components' do
      expect(runtime.configuration).to be(configuration)
      expect(runtime.send(:components)).to be(components)
    end

    it 'it does not trigger 2-step component initialization' do
      expect(components).to_not receive(:startup!)

      runtime
    end
  end

  context '#startup!' do
    subject(:startup!) { runtime.startup! }

    it 'delegates to @components' do
      expect(components).to receive(:startup!).with(configuration)

      startup!
    end
  end

  [
    :health_metrics,
    :logger,
    :profiler,
    :runtime_metrics,
    :tracer,
    :shutdown!
  ]
    .each do |method_name|
    describe "##{method_name}" do
      it "delegates to components.#{method_name}" do
        expect(components).to receive(method_name)

        runtime.public_send(method_name)
      end
    end
  end
end

RSpec.describe Datadog::Tracing::Runtime, :integration do
  subject(:runtime) { described_class.new }
  let(:configuration) { runtime.configuration }

  def components
    runtime.send(:components)
  end

  context '#configure' do
    context 'with default arguments' do
      subject(:configure) { runtime.configure }

      before do
        allow(Datadog::Configuration::Components).to receive(:new)
                                                       .and_wrap_original do |m, *args|
          new_components = m.call(*args)
          allow(new_components).to receive(:shutdown!)
          allow(new_components).to receive(:startup!)
          new_components
        end
      end

      let!(:original_components) { components }

      context 'and components have been initialized' do
        it do
          # Components should have changed
          expect { configure }
            .to change { components }
                  .from(original_components)

          new_components = components
          expect(new_components).to_not be(original_components)

          # Old components should shutdown, new components should startup
          expect(original_components)
            .to have_received(:shutdown!)
                  .with(new_components)
                  .ordered

          expect(new_components)
            .to have_received(:startup!)
                  .with(configuration)
                  .ordered

          expect(new_components).to_not have_received(:shutdown!)
        end
      end

      context 'when a target is configured' do
        subject(:configure) { runtime.configure(object, options) }

        let(:object) { double('object') }
        let(:options) { {} }

        let(:components) { double } # Ensure Components does not receive any messages

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
    end
  end
end
