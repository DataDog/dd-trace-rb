require 'spec_helper'

require 'ddtrace'

RSpec.describe Datadog::Configuration::Option do
  subject(:option) { described_class.new(definition, context) }
  let(:definition) do
    instance_double(
      Datadog::Configuration::OptionDefinition,
      default_value: default_value,
      delegate_to: delegate,
      on_set: nil,
      resetter: nil,
      setter: setter
    )
  end
  let(:default_value) { double('default value') }
  let(:delegate) { nil }
  let(:setter) { proc { setter_value } }
  let(:setter_value) { double('setter_value') }
  let(:context) { double('configuration object') }

  describe '#initialize' do
    it { expect(option.definition).to be(definition) }
  end

  describe '#set' do
    subject(:set) { option.set(value) }
    let(:value) { double('value') }

    context 'when no value has been set' do
      before do
        allow(definition).to receive(:on_set).and_return nil
        expect(context).to receive(:instance_exec) do |*args, &block|
          expect(args.first).to be(value)
          expect(block).to be setter
          setter.call
        end
      end

      it { is_expected.to be(setter_value) }

      context 'when an :on_set event is defined' do
        let(:on_set) { proc { on_set_value } }
        let(:on_set_value) { double('on_set_value') }

        before do
          allow(definition).to receive(:on_set).and_return(on_set)

          expect(context).to receive(:instance_exec) do |*args, &block|
            expect(args.first).to be(setter_value)
            expect(block).to be on_set
            on_set.call
          end
        end

        context 'then #get is invoked' do
          subject(:get) { option.get }
          before { set }
          it { is_expected.to be(setter_value) }
        end
      end
    end

    context 'when a value has already been set' do
      let(:old_value) { double('old value') }

      context 'when an :on_set event is not defined' do
        before do
          allow(context).to receive(:instance_exec)
          allow(definition).to receive(:on_set).and_return nil

          # Set original value
          allow(context).to receive(:instance_exec)
            .with(old_value, nil)
            .and_return(old_value)
          option.set(old_value)
          expect(option.get).to be old_value

          # Stub new value
          allow(context).to receive(:instance_exec)
            .with(value, old_value)
            .and_return(value)
        end

        it 'invokes the setter with both old and new values' do
          # Set new value
          is_expected.to be value
          expect(context).to have_received(:instance_exec)
            .with(value, old_value)
        end
      end

      context 'when an :on_set event is defined' do
        let(:on_set) { proc { on_set_value } }
        let(:on_set_value) { double('on_set_value') }

        before do
          allow(definition).to receive(:on_set).and_return(on_set)

          allow(context).to receive(:instance_exec) do |*args, &block|
            if args.first == old_value
              # Invoked only during setup
              old_value
            elsif block == setter && args.first == value
              # Invoked first
              expect(args).to include(value, old_value)
              setter.call
            elsif block == on_set && args.first == setter_value
              # Invoked second
              expect(args).to include(setter_value, old_value)
              expect(block).to be on_set
              on_set.call
            else
              # Unknown test scenario
              raise ArgumentError
            end
          end

          option.set(old_value)
        end

        context 'then #get is invoked' do
          subject(:get) { option.get }
          before { set }
          it { is_expected.to be(setter_value) }
        end
      end
    end
  end

  describe '#get' do
    subject(:get) { option.get }

    context 'when #set' do
      context 'hasn\'t been called' do
        before do
          expect(context).to receive(:instance_exec) do |*args, &block|
            expect(args.first).to be(default_value)
            expect(block).to be setter
            default_value
          end
        end

        it { is_expected.to be(default_value) }

        context 'and #get is called twice' do
          before do
            expect(definition).to receive(:default_value)
              .once
              .and_return(default_value)
          end

          it 'keeps and re-uses the same default object' do
            is_expected.to be default_value
            expect(option.get).to be default_value
          end
        end
      end

      context 'has been called' do
        let(:value) { double('value') }

        before do
          expect(context).to receive(:instance_exec) do |*args, &block|
            expect(args.first).to be(value)
            expect(block).to be setter
            setter.call
          end

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

      before do
        allow(definition).to receive(:resetter).and_return nil
        allow(context).to receive(:instance_exec).with(value, nil, &setter)
        allow(context).to receive(:instance_exec).with(default_value, nil, &setter).and_return(default_value)
        option.set(value)
      end

      context 'and no resetter is defined' do
        context 'then #get is invoked' do
          subject(:get) { option.get }
          before { reset }
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
          before { reset }
          it { is_expected.to be(resetter_value) }
        end
      end
    end
  end
end
