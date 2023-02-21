# typed: ignore

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/component'

RSpec.describe Datadog::AppSec::Component do
  describe '.build_appsec_component' do
    context 'when appsec is enabled' do
      it 'returns a Datadog::AppSec::Component instance' do
        settings = double('AppSec::Settings', appsec: double('enabled', enabled: true))
        component = described_class.build_appsec_component(settings)
        expect(component).to be_a(described_class)
      end
    end

    context 'when appsec is not enabled' do
      it 'returns nil' do
        settings = double('AppSec::Settings', appsec: double('enabled', enabled: false))
        component = described_class.build_appsec_component(settings)
        expect(component).to be_nil
      end
    end
  end

  describe '#shutdown!' do
    context 'when processor is not nil' do
      it 'finalize processor' do
        settings = double('AppSec::Settings')
        processor = double('AppSec::Processor')
        component = described_class.new(settings)

        expect(component).to receive(:processor).twice.and_return(processor)
        expect(processor).to receive(:finalize)
        component.shutdown!
      end
    end

    context 'when processor is nil' do
      it 'do not finalize processor' do
        settings = double('AppSec::Settings')
        component = described_class.new(settings)

        expect(component).to receive(:processor).and_return(nil)
        expect_any_instance_of(Datadog::AppSec::Processor).to_not receive(:finalize)
        component.shutdown!
      end
    end
  end
end
