require 'spec_helper'

require 'ddtrace'

RSpec.describe Datadog::Configuration::Option do
  subject(:option) { described_class.new(definition, context) }
  let(:definition) do
    instance_double(
      Datadog::Configuration::OptionDefinition,
      default_value: default_value,
      resetter: nil,
      setter: setter
    )
  end
  let(:default_value) { double('default value') }
  let(:setter) { proc { setter_value } }
  let(:setter_value) { double('setter_value') }
  let(:context) { double('configuration object') }

  describe '#initialize' do
    it { expect(option.definition).to be(definition) }
  end

  describe '#set' do
    subject(:set) { option.set(value) }
    let(:value) { double('value') }

    before(:each) { expect(context).to receive(:instance_exec).with(value, &setter) }

    it { is_expected.to be(setter_value) }
  end

  describe '#get' do
    subject(:get) { option.get }

    context 'when #set' do
      context 'hasn\'t been called' do
        it { is_expected.to be(default_value) }
      end

      context 'has been called' do
        let(:value) { double('value') }

        before(:each) do
          allow(context).to receive(:instance_exec).with(value, &setter)
          option.set(value)
        end

        it { is_expected.to be(setter_value) }
      end
    end
  end

  describe '#reset' do
    subject(:reset) { option.reset }

    context 'when a value has been set' do
      let(:value) { double('value') }

      before(:each) do
        allow(definition).to receive(:resetter).and_return nil
        allow(context).to receive(:instance_exec).with(value, &setter)
        allow(context).to receive(:instance_exec).with(default_value, &setter).and_return(default_value)
        option.set(value)
      end

      context 'and no resetter is defined' do
        context 'then #get is invoked' do
          subject(:get) { option.get }
          before(:each) { reset }
          it { is_expected.to be(default_value) }
        end
      end

      context 'and a resetter is defined' do
        let(:resetter) { proc { resetter_value } }
        let(:resetter_value) { double('resetter_value') }

        before do
          allow(definition).to receive(:resetter).and_return(resetter)

          expect(context).to receive(:instance_exec) do |*args, &block|
            expect(args.first).to be(setter_value)
            expect(block).to be resetter
            resetter.call
          end
        end

        context 'then #get is invoked' do
          subject(:get) { option.get }
          before(:each) { reset }
          it { is_expected.to be(resetter_value) }
        end
      end
    end
  end
end
