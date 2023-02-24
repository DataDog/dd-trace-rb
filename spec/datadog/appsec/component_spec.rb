require 'datadog/appsec/spec_helper'
require 'datadog/appsec/component'

RSpec.describe Datadog::AppSec::Component do
  describe '.build_appsec_component' do
    let(:settings) do
      Datadog::AppSec::Configuration::Settings.new.merge(
        Datadog::AppSec::Configuration::DSL.new.tap do |appsec|
          appsec.enabled = appsec_enabled
        end
      )
    end
    context 'when appsec is enabled' do
      let(:appsec_enabled) { true }
      it 'returns a Datadog::AppSec::Component instance' do
        component = described_class.build_appsec_component(settings)
        expect(component).to be_a(described_class)
      end

      context 'when processor is ready' do
        it 'returns a Datadog::AppSec::Component with a processor instance' do
          expect_any_instance_of(Datadog::AppSec::Processor).to receive(:ready?).and_return(true)
          component = described_class.build_appsec_component(settings)

          expect(component.processor).to be_a(Datadog::AppSec::Processor)
        end
      end

      context 'when processor fail to instanciate' do
        it 'returns a Datadog::AppSec::Component with a nil processor' do
          expect_any_instance_of(Datadog::AppSec::Processor).to receive(:ready?).and_return(false)
          component = described_class.build_appsec_component(settings)

          expect(component.processor).to be_nil
        end
      end
    end

    context 'when appsec is not enabled' do
      let(:appsec_enabled) { false }

      it 'returns nil' do
        component = described_class.build_appsec_component(settings)
        expect(component).to be_nil
      end
    end
  end

  describe '#shutdown!' do
    context 'when processor is not nil and ready' do
      it 'finalizes the processor' do
        processor = instance_double(Datadog::AppSec::Processor)

        component = described_class.new(processor: processor)
        expect(processor).to receive(:ready?).and_return(true)
        expect(processor).to receive(:finalize)
        component.shutdown!
      end
    end

    context 'when processor is not ready' do
      it 'does not finalize the processor' do
        processor = instance_double(Datadog::AppSec::Processor)
        expect(processor).to receive(:ready?).and_return(false)

        component = described_class.new(processor: processor)

        expect(processor).to_not receive(:finalize)
        component.shutdown!
      end
    end

    context 'when processor is nil' do
      it 'does not finalize the processor' do
        component = described_class.new(processor: nil)

        expect_any_instance_of(Datadog::AppSec::Processor).to_not receive(:finalize)
        component.shutdown!
      end
    end
  end
end
