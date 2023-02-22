# typed: ignore

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/component'

RSpec.describe Datadog::AppSec::Component do
  describe '.build_appsec_component' do
    context 'when appsec is enabled' do
      it 'returns a Datadog::AppSec::Component instance' do
        settings = Datadog::AppSec::Configuration::Settings.new.merge(
          Datadog::AppSec::Configuration::DSL.new.tap do |it|
            it.enabled = true
          end
        )
        component = described_class.build_appsec_component(settings)
        expect(component).to be_a(described_class)
      end
    end

    context 'when appsec is not enabled' do
      it 'returns nil' do
        settings = Datadog::AppSec::Configuration::Settings.new.merge(
          Datadog::AppSec::Configuration::DSL.new.tap do |it|
            it.enabled = false
          end
        )
        component = described_class.build_appsec_component(settings)
        expect(component).to be_nil
      end
    end
  end

  describe '#shutdown!' do
    context 'when processor is not nil' do
      it 'finalizes the processor' do
        processor = instance_double(Datadog::AppSec::Processor)

        component = described_class.new(processor: processor)

        expect(processor).to receive(:finalize)
        component.shutdown!
      end
    end
  end
end
