require 'spec_helper'

require 'ddtrace'

RSpec.describe Datadog::Core::Configuration::Option do
  subject(:option) { described_class.new(definition, context) }

  let(:definition) do
    instance_double(
      Datadog::Core::Configuration::OptionDefinition,
      name: :test_name,
      default: default,
      experimental_default_proc: experimental_default_proc,
      delegate_to: delegate,
      on_set: nil,
      resetter: nil,
      setter: setter
    )
  end
  let(:default) { double('default') }
  let(:experimental_default_proc) { nil }
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

      context 'with precedence REMOTE_CONFIGURATION' do
        let(:setter) { proc { |value| value } }

        before do
          option.set(:original_value, precedence: Datadog::Core::Configuration::Option::Precedence::REMOTE_CONFIGURATION)
        end

        it 'overrides with value with the same precedence' do
          option.set(:override, precedence: Datadog::Core::Configuration::Option::Precedence::REMOTE_CONFIGURATION)
          expect(option.get).to eq(:override)
        end

        it 'does not override with value with precedence PROGRAMMATIC' do
          option.set(:override, precedence: Datadog::Core::Configuration::Option::Precedence::PROGRAMMATIC)
          expect(option.get).to eq(:original_value)
        end

        it 'does not override with value with precedence DEFAULT' do
          option.set(:override, precedence: Datadog::Core::Configuration::Option::Precedence::DEFAULT)
          expect(option.get).to eq(:original_value)
        end

        it 'does not record info log for successful override' do
          allow(Datadog.logger).to receive(:info)
          option.set(:override, precedence: Datadog::Core::Configuration::Option::Precedence::REMOTE_CONFIGURATION)
          expect(Datadog.logger).to_not receive(:info)
        end

        it 'records info log for ignored override' do
          allow(Datadog.logger).to receive(:info)
          option.set(:override, precedence: Datadog::Core::Configuration::Option::Precedence::DEFAULT)
          expect(Datadog.logger).to have_received(:info) do |&block|
            expect(block.call).to include("Option 'test_name' not changed to 'override'")
          end
        end
      end

      context 'with precedence PROGRAMMATIC' do
        let(:setter) { proc { |value| value } }

        before do
          option.set(:original_value, precedence: Datadog::Core::Configuration::Option::Precedence::PROGRAMMATIC)
        end

        it 'overrides with value with precedence REMOTE_CONFIGURATION' do
          option.set(:override, precedence: Datadog::Core::Configuration::Option::Precedence::REMOTE_CONFIGURATION)
          expect(option.get).to eq(:override)
        end

        it 'overrides with value with the same precedence' do
          option.set(:override, precedence: Datadog::Core::Configuration::Option::Precedence::PROGRAMMATIC)
          expect(option.get).to eq(:override)
        end

        it 'does not override with value with precedence DEFAULT' do
          option.set(:override, precedence: Datadog::Core::Configuration::Option::Precedence::DEFAULT)
          expect(option.get).to eq(:original_value)
        end
      end

      context 'with precedence DEFAULT' do
        let(:setter) { proc { |value| value } }

        before do
          option.set(:original_value, precedence: Datadog::Core::Configuration::Option::Precedence::DEFAULT)
        end

        it 'overrides with value with precedence REMOTE_CONFIGURATION' do
          option.set(:override, precedence: Datadog::Core::Configuration::Option::Precedence::REMOTE_CONFIGURATION)
          expect(option.get).to eq(:override)
        end

        it 'overrides with value with precedence PROGRAMMATIC' do
          option.set(:override, precedence: Datadog::Core::Configuration::Option::Precedence::PROGRAMMATIC)
          expect(option.get).to eq(:override)
        end

        it 'overrides with value with the same precedence' do
          option.set(:override, precedence: Datadog::Core::Configuration::Option::Precedence::DEFAULT)
          expect(option.get).to eq(:override)
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
            expect(args.first).to be(default)
            expect(block).to be setter
            default
          end
        end

        it { is_expected.to be(default) }

        context 'and #get is called twice' do
          before do
            allow(definition).to receive(:default)
              .and_return(default)
          end

          it 'keeps and re-uses the same default object' do
            is_expected.to be default
            expect(option.get).to be default
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
        allow(context).to receive(:instance_exec).with(default, nil, &setter).and_return(default)
        option.set(value)
      end

      context 'and no resetter is defined' do
        context 'then #get is invoked' do
          subject(:get) { option.get }

          before { reset }

          it { is_expected.to be(default) }
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

      it 'resets precedence to DEFAULT' do
        reset
        expect(option.send(:precedence_set)).to eq(Datadog::Core::Configuration::Option::Precedence::DEFAULT)
      end
    end
  end

  describe '#default_value' do
    subject(:default_value) { option.default_value }

    let(:default) { double('default') }

    context 'when default is a block' do
      let(:default) { proc {} }
      let(:block_default) { double('block default') }

      before do
        expect(context).to receive(:instance_eval) do |&block|
          expect(block).to be default
          block_default
        end
      end

      it { is_expected.to be block_default }
    end

    context 'when default is not a block' do
      it { is_expected.to be default }
    end

    context 'when experimental_default_proc is defined' do
      let(:experimental_default_proc) { proc { 'experimental_default_proc' } }

      it { is_expected.to be experimental_default_proc }
    end
  end
end
