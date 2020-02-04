require 'spec_helper'

require 'ddtrace/contrib/configuration/resolver'

RSpec.describe Datadog::Contrib::Configuration::Resolver do
  subject(:resolver) { described_class.new(&default_config_block) }
  let(:default_config_block) { proc { config_class.new } }
  let(:config_class) { Class.new }

  describe '.new' do
    context 'when given no arguments' do
      it { expect { described_class.new }.to raise_error(ArgumentError) }
    end

    context 'when given a block' do
      it { is_expected.to be_a_kind_of(described_class) }
      it { expect(resolver.configurations).to include(default: kind_of(config_class)) }
    end
  end

  describe '#resolve' do
    subject(:resolve) { resolver.resolve(key) }
    let(:key) { double('key') }

    context 'when it doesn\'t match a configuration' do
      it { is_expected.to be resolver.configurations[:default] }
    end

    context 'when it matches a configuration' do
      let(:matching_config) { config_class.new }
      before { resolver.add(key, matching_config) }
      it { is_expected.to be matching_config }
    end
  end

  describe '#add' do
    let(:key) { double('key') }

    context 'given a key' do
      subject(:add) { resolver.add(key) }
      it { expect { add }.to(change { resolver.resolve(key).object_id }) }
    end

    context 'given a key and configuration' do
      subject(:add) { resolver.add(key, added_config) }
      let(:added_config) { instance_double(config_class) }

      it do
        expect { add }.to change { resolver.resolve(key) }
          .from(resolver.configurations[:default])
          .to(added_config)
      end
    end
  end

  describe '#match?' do
    subject(:resolve) { resolver.match?(key) }
    let(:key) { double('key') }

    context 'when it doesn\'t match a configuration' do
      it { is_expected.to be false }
    end

    context 'when it matches a configuration' do
      before { resolver.add(key) }
      it { is_expected.to be true }
    end
  end

  describe '#new_default_configuration' do
    subject(:new_default_configuration) { resolver.new_default_configuration }

    it { is_expected.to be_a_kind_of(config_class) }
    it 'doesn\'t return the same object twice' do
      first = resolver.new_default_configuration
      second = resolver.new_default_configuration
      expect(first).to_not be(second)
    end
  end
end
