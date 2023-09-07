require 'spec_helper'

require 'ddtrace'

RSpec.describe Datadog::Core::Configuration::OptionDefinition do
  subject(:definition) { described_class.new(name, meta, &block) }

  let(:name) { :enabled }
  let(:meta) { {} }
  let(:block) { nil }

  describe '#default' do
    subject(:default) { definition.default }

    context 'when not initialized with a value' do
      it { is_expected.to be nil }
    end

    context 'when initialized with a value' do
      let(:meta) { { default: default_value } }
      let(:default_value) { double('default') }

      it { is_expected.to be default_value }
    end
  end

  describe '#name' do
    subject(:result) { definition.name }

    context 'when given a String' do
      let(:name) { 'enabled' }

      it { is_expected.to be name.to_sym }
    end

    context 'when given a Symbol' do
      let(:name) { :enabled }

      it { is_expected.to be name }
    end
  end

  describe '#after_set' do
    subject(:after_set) { definition.after_set }

    context 'when given a value' do
      let(:meta) { { after_set: after_set_value } }
      let(:after_set_value) { double('after_set') }

      it { is_expected.to be after_set_value }
    end

    context 'when not initialized' do
      it { is_expected.to be nil }
    end
  end

  describe '#setter' do
    subject(:setter) { definition.setter }

    context 'when given a value' do
      let(:meta) { { setter: setter_value } }
      let(:setter_value) { double('setter') }

      it { is_expected.to be setter_value }
    end

    context 'when initialized with a block' do
      let(:block) { proc {} }

      it { is_expected.to be block }
    end

    context 'when not initialized' do
      it { is_expected.to be described_class::IDENTITY }
    end
  end

  describe '#resetter' do
    subject(:resetter) { definition.resetter }

    context 'when given a value' do
      let(:meta) { { resetter: resetter_value } }
      let(:resetter_value) { double('resetter') }

      it { is_expected.to be resetter_value }
    end

    context 'when not initialized' do
      it { is_expected.to be nil }
    end
  end

  describe '#type' do
    subject(:type) { definition.type }

    context 'when given a value' do
      let(:meta) { { type: type_value } }
      let(:type_value) { double('type') }

      it { is_expected.to be type_value }
    end

    context 'when not initialized' do
      it { is_expected.to be nil }
    end
  end

  describe '#build' do
    subject(:build) { definition.build(context) }

    let(:context) { double('context') }
    let(:option) { instance_double(Datadog::Core::Configuration::Option) }

    before do
      expect(Datadog::Core::Configuration::Option).to receive(:new)
        .with(definition, context)
        .and_return(option)
    end

    it { is_expected.to be option }
  end
end

RSpec.describe Datadog::Core::Configuration::OptionDefinition::Builder do
  subject(:builder) { described_class.new(name, initialize_options, &initialize_block) }

  let(:name) { :enabled }
  let(:initialize_options) { {} }
  let(:initialize_block) { nil }

  describe '#initialize' do
    context 'given no arguments' do
      context 'creates a Builder' do
        context 'where #helpers' do
          subject(:helpers) { builder.helpers }

          it { is_expected.to eq({}) }
        end

        context 'where #to_definition' do
          subject(:definition) { builder.to_definition }

          it { is_expected.to be_a_kind_of(Datadog::Core::Configuration::OptionDefinition) }

          it 'generates an OptionDefinition with defaults' do
            is_expected.to have_attributes(
              default: nil,
              default_proc: nil,
              name: name,
              after_set: nil,
              resetter: nil,
              setter: Datadog::Core::Configuration::OptionDefinition::IDENTITY,
              type: nil,
              type_options: {},
              env: nil,
              deprecated_env: nil,
              env_parser: nil
            )
          end
        end
      end
    end

    context 'given a block' do
      it 'yields to the block' do
        expect { |b| described_class.new(name, initialize_options, &b) }.to yield_with_args(kind_of(described_class))
      end
    end

    context 'given options and a block' do
      context 'that override one another' do
        let(:initialize_options) { { default: true } }
        let(:initialize_block) { proc { |o| o.default false } }

        describe '#to_definition' do
          subject(:definition) { builder.to_definition }

          it 'yields an OptionDefinition with the block\'s value' do
            is_expected.to have_attributes(default: false)
          end
        end
      end
    end

    context 'validate_options!' do
      context 'when default and default_proc is provided' do
        let(:initialize_block) do
          proc do |o|
            o.default false
            o.default_proc { true }
          end
        end

        it do
          expect do
            is_expected
          end.to raise_error(described_class::InvalidOptionError)
        end
      end
    end
  end

  describe '#default' do
    subject(:default) { builder.default(value, &block) }

    let(:value) { nil }
    let(:block) { nil }

    context 'given a value' do
      let(:value) { true }

      it { is_expected.to be value }
    end

    context 'given a block' do
      let(:block) { proc { false } }

      it { is_expected.to be block }
    end

    context 'given a value and block' do
      let(:value) { true }
      let(:block) { proc { false } }

      it { is_expected.to be block }
    end
  end

  describe '#default_proc' do
    subject(:default_proc) { builder.default_proc(&block) }

    context 'given a block' do
      let(:block) { proc { false } }

      it { is_expected.to be block }
    end
  end

  describe '#helper' do
    subject(:helper) { builder.helper(name, *args, &block) }

    let(:name) { :enabled }
    let(:args) { [] }
    let(:block) { nil }

    context 'given false and no block' do
      let(:args) { [false] }

      it 'defines a nil helper' do
        is_expected.to be nil
        expect(builder.helpers).to include(name => nil)
      end
    end

    context 'given a block' do
      let(:block) { proc { :bar } }

      it 'defines a helper' do
        is_expected.to be block
        expect(builder.helpers).to include(name => block)
      end
    end
  end

  describe '#lazy' do
    it 'logs deprecation warning' do
      expect(Datadog::Core).to receive(:log_deprecation)
      builder.lazy
    end
  end

  describe '#after_set' do
    subject(:after_set) { builder.after_set(&block) }

    let(:block) { proc {} }

    it { is_expected.to be block }
  end

  describe '#resetter' do
    subject(:resetter) { builder.resetter(&block) }

    let(:block) { proc {} }

    it { is_expected.to be block }
  end

  describe '#setter' do
    subject(:setter) { builder.setter(&block) }

    let(:block) { proc {} }

    it { is_expected.to be block }
  end

  describe '#type' do
    subject(:type) { builder.type(value, **opts) }
    let(:value) { nil }
    let(:opts) { {} }

    context 'given a value' do
      let(:value) { :string }

      it { is_expected.to be value }
      it { expect { type }.to change { builder.meta[:type] }.from(nil).to(value) }
    end

    context 'given options' do
      let(:value) { :string }
      let(:opts) { { nilable: true } }

      it { is_expected.to be value }
      it { expect { type }.to change { builder.meta[:type] }.from(nil).to(value) }
      it { expect { type }.to change { builder.meta[:type_options] }.from({}).to(opts) }
    end
  end

  describe '#env' do
    subject(:env) { builder.env(value) }

    context 'given a value' do
      let(:value) { 'TEST' }

      it { is_expected.to be value }
    end
  end

  describe '#deprecated_env' do
    subject(:deprecated_env) { builder.deprecated_env(value) }

    context 'given a value' do
      let(:value) { 'TEST' }

      it { is_expected.to be value }
    end
  end

  describe '#env_parser' do
    subject(:env_parser) { builder.env_parser(&block) }

    context 'given a block' do
      let(:block) { proc { false } }

      it { is_expected.to be block }
    end
  end

  describe '#apply_options!' do
    subject(:apply_options!) { builder.apply_options!(options) }

    let(:options) { {} }

    context 'given :default' do
      let(:options) { { default: value } }
      let(:value) { double('value') }

      it do
        expect(builder).to receive(:default).with(value)
        apply_options!
      end
    end

    context 'given :after_set' do
      let(:options) { { after_set: value } }
      let(:value) { proc {} }

      it do
        expect(builder).to receive(:after_set) do |&block|
          expect(block).to be value
        end

        apply_options!
      end
    end

    context 'given :resetter' do
      let(:options) { { resetter: value } }
      let(:value) { proc {} }

      it do
        expect(builder).to receive(:resetter) do |&block|
          expect(block).to be value
        end

        apply_options!
      end
    end

    context 'given :setter' do
      let(:options) { { setter: value } }
      let(:value) { proc {} }

      it do
        expect(builder).to receive(:setter) do |&block|
          expect(block).to be value
        end

        apply_options!
      end
    end
  end

  describe '#to_definition' do
    subject(:definition) { builder.to_definition }

    let(:option_definition) { instance_double(Datadog::Core::Configuration::OptionDefinition) }

    before do
      expect(Datadog::Core::Configuration::OptionDefinition).to receive(:new)
        .with(name, builder.meta)
        .and_return(option_definition)
    end

    it { is_expected.to be option_definition }
  end

  describe '#meta' do
    subject(:meta) { builder.meta }

    it { is_expected.to be_a_kind_of(Hash) }

    it 'contains the arguments for OptionDefinition' do
      expect(meta.keys).to include(
        :default,
        :default_proc,
        :after_set,
        :resetter,
        :setter,
        :type,
        :type_options,
        :env,
        :deprecated_env,
        :env_parser,
      )
    end
  end
end
