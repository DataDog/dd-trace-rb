require 'spec_helper'

require 'datadog'

RSpec.describe Datadog::Core::Configuration::Option do
  subject(:option) { described_class.new(definition, context) }

  let(:definition) do
    instance_double(
      Datadog::Core::Configuration::OptionDefinition,
      name: :test_name,
      default: default,
      default_proc: default_proc,
      env: env,
      deprecated_env: deprecated_env,
      env_parser: env_parser,
      after_set: nil,
      resetter: nil,
      setter: setter,
      type: type,
      type_options: type_options,
    )
  end
  let(:default) { double('default') }
  let(:default_proc) { nil }
  let(:env) { nil }
  let(:env_parser) { nil }
  let(:type) { nil }
  let(:type_options) { {} }
  let(:deprecated_env) { nil }
  let(:setter) { proc { setter_value } }
  let(:setter_value) { double('setter_value') }
  let(:context) { double('configuration object') }

  # When setting the setting value, we make sure to duplicate it to avoid unwanted modifications
  # to make sure specs pass when comparing result ex. expect(result).to be value
  # we ensure that frozen_or_dup returns the same instance
  before do
    allow(Datadog::Core::Utils::SafeDup).to receive(:frozen_or_dup) do |args, _block|
      args
    end
  end

  describe '#initialize' do
    it { expect(option.definition).to be(definition) }
  end

  describe '#set' do
    subject(:set) { option.set(value) }

    let(:value) { double('value') }

    context 'when no value has been set' do
      before do
        allow(definition).to receive(:after_set).and_return nil
        expect(context).to receive(:instance_exec) do |*args, &block|
          expect(args.first).to be(value)
          expect(block).to be setter
          setter.call
        end
      end

      it { is_expected.to be(setter_value) }

      context 'when an :after_set event is defined' do
        let(:after_set) { proc { after_set_value } }
        let(:after_set_value) { double('after_set_value') }

        before do
          allow(definition).to receive(:after_set).and_return(after_set)

          expect(context).to receive(:instance_exec) do |value, old_value, precedence, &block|
            expect(value).to be(setter_value)
            expect(old_value).to be(nil)
            expect(precedence).to be(Datadog::Core::Configuration::Option::Precedence::PROGRAMMATIC)
            expect(block).to be after_set
            after_set.call
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

      context 'when an :after_set event is not defined' do
        before do
          allow(context).to receive(:instance_exec)
          allow(definition).to receive(:after_set).and_return nil

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

      context 'when an :after_set event is defined' do
        let(:after_set) { proc { after_set_value } }
        let(:after_set_value) { double('after_set_value') }

        before do
          allow(definition).to receive(:after_set).and_return(after_set)

          allow(context).to receive(:instance_exec) do |*args, &block|
            if args.first == old_value
              # Invoked only during setup
              old_value
            elsif block == setter && args.first == value
              # Invoked first
              expect(args).to include(value, old_value)
              setter.call
            elsif block == after_set && args.first == setter_value
              # Invoked second
              expect(args).to include(
                setter_value,
                old_value,
                Datadog::Core::Configuration::Option::Precedence::PROGRAMMATIC
              )
              expect(block).to be after_set
              after_set.call
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
        let(:after_set) { double('after_set block') }
        let(:setter) { proc { |value| value } }

        before do
          after_set_double = after_set
          allow(definition).to receive(:after_set).and_return(proc { |*args| after_set_double.call(*args) })

          expect(after_set).to receive(:call).with(
            :original_value,
            nil,
            Datadog::Core::Configuration::Option::Precedence::REMOTE_CONFIGURATION
          )
          allow(after_set).to receive(:call).with(:override, :original_value, anything)

          option.set(:original_value, precedence: Datadog::Core::Configuration::Option::Precedence::REMOTE_CONFIGURATION)
          allow(Datadog.logger).to receive(:info)
        end

        it 'overrides with value with the same precedence' do
          expect(after_set).to receive(:call).with(
            :override,
            :original_value,
            Datadog::Core::Configuration::Option::Precedence::REMOTE_CONFIGURATION
          )
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
        let(:after_set) { double('after_set block') }
        let(:setter) { proc { |value| value } }

        before do
          after_set_double = after_set
          allow(definition).to receive(:after_set).and_return(proc { |*args| after_set_double.call(*args) })

          expect(after_set).to receive(:call).with(
            :original_value,
            nil,
            Datadog::Core::Configuration::Option::Precedence::PROGRAMMATIC
          )

          option.set(:original_value, precedence: Datadog::Core::Configuration::Option::Precedence::PROGRAMMATIC)
          allow(Datadog.logger).to receive(:info)
        end

        it 'overrides with value with precedence REMOTE_CONFIGURATION' do
          expect(after_set).to receive(:call).with(
            :override,
            :original_value,
            Datadog::Core::Configuration::Option::Precedence::REMOTE_CONFIGURATION
          )
          option.set(:override, precedence: Datadog::Core::Configuration::Option::Precedence::REMOTE_CONFIGURATION)
          expect(option.get).to eq(:override)
        end

        it 'overrides with value with the same precedence' do
          expect(after_set).to receive(:call).with(
            :override,
            :original_value,
            Datadog::Core::Configuration::Option::Precedence::PROGRAMMATIC
          )
          option.set(:override, precedence: Datadog::Core::Configuration::Option::Precedence::PROGRAMMATIC)
          expect(option.get).to eq(:override)
        end

        it 'does not override with value with precedence DEFAULT' do
          option.set(:override, precedence: Datadog::Core::Configuration::Option::Precedence::DEFAULT)
          expect(option.get).to eq(:original_value)
        end
      end

      context 'with precedence DEFAULT' do
        let(:after_set) { instance_double(Proc) }
        let(:setter) { proc { |value| value } }

        before do
          after_set_double = after_set
          allow(definition).to receive(:after_set).and_return(proc { |*args| after_set_double.call(*args) })

          expect(after_set).to receive(:call).with(
            :original_value,
            nil,
            Datadog::Core::Configuration::Option::Precedence::DEFAULT
          )

          option.set(:original_value, precedence: Datadog::Core::Configuration::Option::Precedence::DEFAULT)
        end

        it 'overrides with value with precedence REMOTE_CONFIGURATION' do
          expect(after_set).to receive(:call).with(
            :override,
            :original_value,
            Datadog::Core::Configuration::Option::Precedence::REMOTE_CONFIGURATION
          )
          option.set(:override, precedence: Datadog::Core::Configuration::Option::Precedence::REMOTE_CONFIGURATION)
          expect(option.get).to eq(:override)
        end

        it 'overrides with value with precedence PROGRAMMATIC' do
          expect(after_set).to receive(:call).with(
            :override,
            :original_value,
            Datadog::Core::Configuration::Option::Precedence::PROGRAMMATIC
          )
          option.set(:override, precedence: Datadog::Core::Configuration::Option::Precedence::PROGRAMMATIC)
          expect(option.get).to eq(:override)
        end

        it 'overrides with value with the same precedence' do
          expect(after_set).to receive(:call).with(
            :override,
            :original_value,
            Datadog::Core::Configuration::Option::Precedence::DEFAULT
          )
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
        end

        context 'Integer' do
          let(:type) { :int }

          context 'valid value' do
            let(:value) { 1 }

            it 'does not raise exception' do
              expect { set }.not_to raise_exception
            end
          end

          context 'invalid value' do
            let(:value) { true }

            it 'raise exception' do
              expect { set }.to raise_exception(ArgumentError)
            end

            context 'that is a float' do
              let(:value) { 10.1 }

              it 'raises exception' do
                expect { set }.to raise_exception(ArgumentError)
              end
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

            context 'that is an integer' do
              let(:value) { 10 }

              it 'does not raise exception' do
                expect { set }.not_to raise_exception
              end
            end

            context 'that is a rational' do
              let(:value) { 1/3r }

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

  describe '#unset' do
    before { allow(Datadog.logger).to receive(:info) }

    # Sanity check for the combinatorial test setup that follows
    it 'expect precedence list to not be empty' do
      expect(Datadog::Core::Configuration::Option::Precedence::LIST).to_not be_empty
    end

    # Test all combinations of precedences to seed the Option object with all possible values set.
    # For each combination, try to `unset` on every precedence.
    #
    # For example, if we have 2 precedences, `default` and `rc`,
    # for an existing Option:
    #
    # | With these precedences set | `#unset` precedence | Assert that     |
    # |----------------------------|---------------------|-----------------|
    # | (empty)                    | rc                  | no change       |
    # | (empty)                    | default             | no change       |
    # | rc                         | rc                  | Option is reset |
    # | rc                         | default             | no change       |
    # | default                    | rc                  | no change       |
    # | default                    | default             | Option is reset |
    # | rc, default                | rc                  | default         |
    # | rc, default                | default             | rc              |
    {
      no_precedence: [],
      remote_configuration: [Datadog::Core::Configuration::Option::Precedence::REMOTE_CONFIGURATION],
      programmatic: [Datadog::Core::Configuration::Option::Precedence::PROGRAMMATIC],
      default: [Datadog::Core::Configuration::Option::Precedence::DEFAULT],
      remote_and_programmatic: [
        Datadog::Core::Configuration::Option::Precedence::REMOTE_CONFIGURATION,
        Datadog::Core::Configuration::Option::Precedence::PROGRAMMATIC
      ],
      remote_and_default: [
        Datadog::Core::Configuration::Option::Precedence::REMOTE_CONFIGURATION,
        Datadog::Core::Configuration::Option::Precedence::DEFAULT
      ],
      programmatic_and_default: [
        Datadog::Core::Configuration::Option::Precedence::PROGRAMMATIC,
        Datadog::Core::Configuration::Option::Precedence::DEFAULT
      ],
      all: [
        Datadog::Core::Configuration::Option::Precedence::REMOTE_CONFIGURATION,
        Datadog::Core::Configuration::Option::Precedence::PROGRAMMATIC,
        Datadog::Core::Configuration::Option::Precedence::DEFAULT
      ]
    }.each do |name, precedences|
      context "for #{name} set" do
        before do
          allow(context).to(receive(:instance_exec)) { |value, _| value }

          # See this Option with many values set a different precedences.
          precedences.each do |precedence|
            # For convenience, the option value is set to the same object as the precedence.
            value = precedence

            @highest_value ||= value
            option.set(value, precedence: precedence)
          end
        end

        # Far all scenarios, try to remove each precedence and assert the correct behavior.
        Datadog::Core::Configuration::Option::Precedence::LIST.each do |precedence|
          context "unsetting '#{precedence[1]}'" do
            subject!(:unset) { option.unset(precedence) }
            let(:precedence) { precedence }
            let(:get) { option.get }

            if precedences.empty?
              context 'when no value is set' do
                it 'resets the option' do
                  expect(get).to eq(default)
                  expect(option.send(:precedence_set)).to eq(Datadog::Core::Configuration::Option::Precedence::DEFAULT)
                end
              end
            elsif precedence < precedences[0]
              context 'when a value with lower precedence is unset' do
                it 'does not modify the option value' do
                  expect(get).to eq(@highest_value)
                  expect(option.send(:precedence_set)).to eq(precedences[0])
                end
              end
            elsif precedence == precedences[0]
              context 'the highest precedence value is unset' do
                if precedences.size == 1
                  context 'removing the only value set' do
                    it 'resets the option' do
                      expect(get).to eq(default)
                      expect(option.send(:precedence_set)).to eq(Datadog::Core::Configuration::Option::Precedence::DEFAULT)
                    end
                  end
                else
                  it 'falls back to lower precedence value' do
                    expect(get).to eq(precedences[1])
                    expect(option.send(:precedence_set)).to eq(precedences[1])
                  end
                end
              end
            elsif precedence > precedences[0]
              context 'when a nonexistent value with higher precedence is unset' do
                it 'does not modify the option value' do
                  expect(get).to eq(@highest_value)
                  expect(option.send(:precedence_set)).to eq(precedences[0])
                end
              end
            end
          end
        end
      end
    end

    context 'with a custom setter' do
      let(:setter) { ->(value, _) { value + '+setter' } }

      it 'invokes the setter only once when restoring a value' do
        option.set('prog', precedence: Datadog::Core::Configuration::Option::Precedence::PROGRAMMATIC)
        option.set('default', precedence: Datadog::Core::Configuration::Option::Precedence::DEFAULT)

        option.unset(Datadog::Core::Configuration::Option::Precedence::PROGRAMMATIC)

        expect(option.get).to eq('default+setter')
      end
    end
  end

  describe '#get' do
    subject(:get) { option.get }

    shared_examples_for 'env coercion' do
      context 'when type is defined' do
        context ':hash' do
          let(:type) { :hash }

          context 'value with commas' do
            let(:env_value) { 'key1:value1,key2:value2' }

            it 'coerce value' do
              expect(option.get).to eq({ 'key1' => 'value1', 'key2' => 'value2' })
            end

            context 'remove empty values' do
              let(:env_value) { 'key1:value1,key2:value2,,,key3:value3,' }

              it 'coerce value' do
                expect(option.get).to eq({ 'key1' => 'value1', 'key2' => 'value2', 'key3' => 'value3' })
              end
            end
          end
        end

        context ':int' do
          let(:type) { :int }
          let(:env_value) { '1234' }

          it 'coerce value' do
            expect(option.get).to eq 1234
          end

          context 'with an octal number' do
            let(:env_value) { '010' }
            it 'parses in base 10' do
              expect(option.get).to eq 10
            end
          end

          context 'with a float' do
            let(:env_value) { '10.1' }
            it 'errors' do
              expect { option.get }.to raise_exception(ArgumentError)
            end
          end

          context 'with not a number' do
            let(:env_value) { 'not a number' }
            it 'errors' do
              expect { option.get }.to raise_exception(ArgumentError)
            end
          end
        end

        context ':float' do
          let(:type) { :float }
          let(:env_value) { '12.34' }

          it 'coerce value' do
            expect(option.get).to eq 12.34
          end

          context 'with not a number' do
            let(:env_value) { 'not a number' }
            it 'errors' do
              expect { option.get }.to raise_exception(ArgumentError)
            end
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
            expect { option.get }.to raise_exception(Datadog::Core::Configuration::Option::InvalidDefinitionError)
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
        allow(Datadog.logger).to receive(:warn) # For deprecation warnings
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
        allow(Datadog.logger).to receive(:warn) # For deprecation warnings
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

      context 'with previous value in different precedence' do
        before do
          allow(context).to receive(:instance_exec).with(:value, any_args).and_return(:value)

          option.set(:value, precedence: Datadog::Core::Configuration::Option::Precedence::PROGRAMMATIC)
        end

        it 'resetting removes all old precedence values store' do
          reset

          # For unset to try to restore an old precedence value
          option.set(:value, precedence: Datadog::Core::Configuration::Option::Precedence::REMOTE_CONFIGURATION)
          option.unset(Datadog::Core::Configuration::Option::Precedence::REMOTE_CONFIGURATION)

          # But no values should be stored, thus the default is returned instead
          expect(option.get).to eq(default)
        end
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

    context 'when default_proc is defined' do
      let(:default_proc) { proc { 'default_proc' } }

      it { is_expected.to be default_proc }
    end
  end
end
