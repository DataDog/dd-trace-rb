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
      env: env,
      deprecated_env: deprecated_env,
      env_parser: env_parser,
      delegate_to: delegate,
      on_set: nil,
      resetter: nil,
      setter: setter,
      type: type,
      type_options: type_options,
    )
  end
  let(:default) { double('default') }
  let(:experimental_default_proc) { nil }
  let(:delegate) { nil }
  let(:env) { nil }
  let(:env_parser) { nil }
  let(:type) { nil }
  let(:type_options) { {} }
  let(:deprecated_env) { nil }
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

    context 'value validation' do
      before { allow(context).to receive(:instance_exec) }

      context 'when type is not defined' do
        it 'does not raise exception' do
          expect { set }.not_to raise_exception
        end
      end

      context 'when type is defined' do
        context 'type is invalid value' do
          let(:type) { :nullable_string }
          let(:value) { 'Hello' }
          it 'raise exception' do
            expect { set }.to raise_exception(ArgumentError)
          end

          context 'set DD_EXPERIMENTAL_SKIP_CONFIGURATION_VALIDATION' do
            ['1', 'true'].each do |value|
              context "with #{value}" do
                it 'does not raise exception' do
                  ClimateControl.modify('DD_EXPERIMENTAL_SKIP_CONFIGURATION_VALIDATION' => '1') do
                    expect { set }.to_not raise_exception
                  end
                end
              end
            end

            context 'with something else' do
              it 'does not raise exception' do
                ClimateControl.modify('DD_EXPERIMENTAL_SKIP_CONFIGURATION_VALIDATION' => 'esle') do
                  expect { set }.to raise_exception(ArgumentError)
                end
              end
            end
          end
        end

        context 'Integer' do
          let(:type) { :int }

          context 'valid value' do
            let(:value) { 1 }

            it 'does not raise exception' do
              expect { set }.not_to raise_exception
            end

            context 'allow floats too' do
              let(:value) { 10.0 }

              it 'does not raise exception' do
                expect { set }.not_to raise_exception
              end
            end
          end

          context 'invalid value' do
            let(:value) { true }

            it 'raise exception' do
              expect { set }.to raise_exception(ArgumentError)
            end
          end
        end

        context 'Float' do
          let(:type) { :float }

          context 'valid value' do
            let(:value) { 10.0 }

            it 'does not raise exception' do
              expect { set }.not_to raise_exception
            end

            context 'allow integers too' do
              let(:value) { 10 }

              it 'does not raise exception' do
                expect { set }.not_to raise_exception
              end
            end
          end

          context 'invalid value' do
            let(:value) { true }

            it 'raise exception' do
              expect { set }.to raise_exception(ArgumentError)
            end
          end
        end

        context 'String' do
          let(:type) { :string }

          context 'valid value' do
            let(:value) { 'Hello' }

            it 'does not raise exception' do
              expect { set }.not_to raise_exception
            end
          end

          context 'invalid value' do
            let(:value) { ['Hello'] }

            it 'raise exception' do
              expect { set }.to raise_exception(ArgumentError)
            end
          end
        end

        context 'Array' do
          let(:type) { :array }

          context 'valid value' do
            let(:value) { [] }

            it 'does not raise exception' do
              expect { set }.not_to raise_exception
            end
          end

          context 'invalid value' do
            let(:value) { 'Hello' }

            it 'raise exception' do
              expect { set }.to raise_exception(ArgumentError)
            end
          end
        end

        context 'Hash' do
          let(:type) { :hash }

          context 'valid value' do
            let(:value) { {} }

            it 'does not raise exception' do
              expect { set }.not_to raise_exception
            end
          end

          context 'invalid value' do
            let(:value) { ['Hello'] }

            it 'raise exception' do
              expect { set }.to raise_exception(ArgumentError)
            end
          end
        end

        context 'Bool' do
          let(:type) { :bool }

          context 'valid value' do
            let(:value) { true }

            it 'does not raise exception' do
              expect { set }.not_to raise_exception
            end
          end

          context 'invalid value' do
            let(:value) { :hello }

            it 'raise exception' do
              expect { set }.to raise_exception(ArgumentError)
            end
          end
        end

        context 'Proc' do
          let(:type) { :proc }

          context 'valid value' do
            let(:value) { -> {} }

            it 'does not raise exception' do
              expect { set }.not_to raise_exception
            end
          end

          context 'invalid value' do
            let(:value) { ['Hello'] }

            it 'raise exception' do
              expect { set }.to raise_exception(ArgumentError)
            end
          end
        end

        context 'Symbol' do
          let(:type) { :symbol }

          context 'valid value' do
            let(:value) { :hello }

            it 'does not raise exception' do
              expect { set }.not_to raise_exception
            end
          end

          context 'invalid value' do
            let(:value) { true }

            it 'raise exception' do
              expect { set }.to raise_exception(ArgumentError)
            end
          end
        end

        context 'Nil values' do
          let(:type) { :string }
          let(:type_options) { { nilable: true } }
          let(:value) { nil }

          it 'does not raise exception' do
            expect { set }.to_not raise_exception
          end

          context 'value is not nil' do
            let(:value) { ['Hello'] }

            it 'does raise exception' do
              expect { set }.to raise_exception(ArgumentError)
            end
          end
        end
      end
    end
  end

  describe '#get' do
    subject(:get) { option.get }

    shared_examples_for 'env coercion' do
      context 'when type is defined' do
        context ':int' do
          let(:type) { :int }
          let(:env_value) { '1234' }

          it 'coerce value' do
            expect(option.get).to eq 1234
          end
        end

        context ':float' do
          let(:type) { :float }
          let(:env_value) { '12.34' }

          it 'coerce value' do
            expect(option.get).to eq 12.34
          end
        end

        context ':array' do
          let(:type) { :array }

          context 'value with commas' do
            let(:env_value) { '12,34' }

            it 'coerce value' do
              expect(option.get).to eq ['12', '34']
            end

            context 'remove empty values' do
              let(:env_value) { '12,34,,,56,' }

              it 'coerce value' do
                expect(option.get).to eq ['12', '34', '56']
              end
            end
          end
        end

        context ':bool' do
          let(:type) { :bool }

          context 'with value 1' do
            let(:env_value) { '1' }

            it 'cource value' do
              expect(option.get).to eq true
            end
          end

          context 'with value true' do
            let(:env_value) { 'true' }

            it 'cource value' do
              expect(option.get).to eq true
            end
          end

          context 'other value' do
            let(:env_value) { 'something' }

            it 'cource value' do
              expect(option.get).to eq false
            end
          end
        end

        context 'invalid type' do
          let(:type) { :invalid_type }
          let(:env_value) { '1' }

          it 'raise exception' do
            expect { option.get }.to raise_exception(ArgumentError)
          end
        end
      end
    end

    shared_context 'with env_parser' do
      let(:env_parser) do
        proc do |env_value|
          env_value
        end
      end

      it 'passes the env variable value to the env_parser' do
        expect(context).to receive(:instance_exec) do |*args, &block|
          expect(args.first).to eq(env_value)
          expect(block).to eq env_parser
        end

        get
      end
    end

    context 'when env is defined' do
      before do
        allow(context).to receive(:instance_exec) do |*args|
          args[0]
        end
      end

      let(:env) { 'TEST' }

      context 'when env is not set' do
        it 'use default value' do
          expect(option.get).to be default
        end
      end

      context 'when env is set' do
        around do |example|
          ClimateControl.modify(env => env_value) do
            example.run
          end
        end

        let(:env_value) { 'test' }

        it 'uses env var value' do
          expect(option.get).to eq env_value
        end

        it 'set precedence_set to programmatic' do
          option.get
          expect(option.send(:precedence_set)).to eq described_class::Precedence::PROGRAMMATIC
        end

        it_behaves_like 'env coercion'
        it_behaves_like 'with env_parser'
      end
    end

    context 'when deprecated_env is defined' do
      before do
        allow(context).to receive(:instance_exec) do |*args|
          args[0]
        end
      end

      let(:deprecated_env) { 'TEST' }
      context 'when env var is not set' do
        it do
          expect(option.get).to be default
        end
      end

      context 'when env var is set' do
        around do |example|
          ClimateControl.modify(deprecated_env => env_value) do
            example.run
          end
        end

        let(:env_value) { 'test' }

        it 'uses env var value' do
          expect(option.get).to eq 'test'
        end

        it 'set precedence_set to programmatic' do
          option.get
          expect(option.send(:precedence_set)).to eq described_class::Precedence::PROGRAMMATIC
        end

        it 'log deprecation warning' do
          expect(Datadog::Core).to receive(:log_deprecation)
          option.get
        end

        it_behaves_like 'env coercion'
        it_behaves_like 'with env_parser'
      end
    end

    context 'when env and deprecated_env are defined' do
      before do
        allow(context).to receive(:instance_exec) do |*args|
          args[0]
        end
      end

      let(:env) { 'TEST' }
      let(:deprecated_env) { 'DEPRECATED_TEST' }
      let(:env_value) { 'test' }
      let(:deprecated_env_value) { 'old test' }

      context 'env found' do
        around do |example|
          ClimateControl.modify(env => env_value, deprecated_env => deprecated_env_value) do
            example.run
          end
        end

        it 'uses env var value' do
          expect(option.get).to eq 'test'
        end

        it 'set precedence_set to programmatic' do
          option.get
          expect(option.send(:precedence_set)).to eq described_class::Precedence::PROGRAMMATIC
        end

        it 'do not log deprecation warning' do
          expect(Datadog::Core).to_not receive(:log_deprecation)
          option.get
        end
      end

      context 'env not found and deprecated_env found' do
        around do |example|
          ClimateControl.modify(deprecated_env => deprecated_env_value) do
            example.run
          end
        end

        it 'uses env var value' do
          expect(option.get).to eq 'old test'
        end

        it 'set precedence_set to programmatic' do
          option.get
          expect(option.send(:precedence_set)).to eq described_class::Precedence::PROGRAMMATIC
        end

        it 'log deprecation warning' do
          expect(Datadog::Core).to receive(:log_deprecation)
          option.get
        end
      end

      context 'env and deprecated_env not found' do
        it 'uses default value' do
          expect(option.get).to eq default
        end

        it 'set precedence_set to default' do
          option.get
          expect(option.send(:precedence_set)).to eq described_class::Precedence::DEFAULT
        end

        it 'do not log deprecation warning' do
          expect(Datadog::Core).to_not receive(:log_deprecation)
          option.get
        end
      end
    end

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

          it do
            is_expected.to be(default)
          end
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
          expect(block).to eq(default)
          block_default
        end
      end

      it { is_expected.to be block_default }
    end

    context 'when default is not a block' do
      it do
        is_expected.to be default
      end
    end

    context 'when experimental_default_proc is defined' do
      let(:experimental_default_proc) { proc { 'experimental_default_proc' } }

      it { is_expected.to be experimental_default_proc }
    end
  end
end
