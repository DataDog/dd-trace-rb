# typed: ignore

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/component'

RSpec.describe Datadog::AppSec::Component do
  describe '.build_appsec_component' do
    context 'when appsec is enabled' do
      it 'returns a Datadog::AppSec::Component instance' do
        Datadog.configuration.appsec.enabled = true
        component = described_class.build_appsec_component(Datadog.configuration)
        expect(component).to be_a(described_class)
      end
    end

    context 'when appsec is not enabled' do
      it 'returns nil' do
        Datadog.configuration.appsec.enabled = false
        component = described_class.build_appsec_component(Datadog.configuration)
        expect(component).to be_nil
      end
    end
  end

  describe '#shutdown!' do
    context 'when processor is not nil' do
      it 'finalizes the processor' do
        processor = Datadog::AppSec::Processor.new

        component = described_class.new(processor: processor)

        expect(processor).to receive(:finalize)
        component.shutdown!
      end
    end

    context 'when processor is nil' do
      it 'do not finalizes the processor' do
        component = described_class.new(processor: nil)

        expect_any_instance_of(Datadog::AppSec::Processor).to_not receive(:finalize)
        component.shutdown!
      end
    end
  end
end
