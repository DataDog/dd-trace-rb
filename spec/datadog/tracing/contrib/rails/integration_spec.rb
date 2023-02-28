require 'datadog/tracing/contrib/support/spec_helper'

require 'datadog/tracing/contrib/rails/integration'

RSpec.describe Datadog::Tracing::Contrib::Rails::Integration do
  extend ConfigurationHelpers

  let(:integration) { described_class.new(:rails) }

  describe '.version' do
    subject(:version) { described_class.version }

    context 'when the "railties" gem is loaded' do
      include_context 'loaded gems', railties: described_class::MINIMUM_VERSION
      it { is_expected.to be_a_kind_of(Gem::Version) }
    end

    context 'when the "railties" gem is not loaded' do
      include_context 'loaded gems', railties: nil
      it { is_expected.to be nil }
    end
  end

  describe '.loaded?' do
    subject(:loaded?) { described_class.loaded? }

    context 'when Rails is defined' do
      before { stub_const('Rails', Class.new) }

      it { is_expected.to be true }
    end

    context 'when Rails is not defined' do
      before { hide_const('Rails') }

      it { is_expected.to be false }
    end
  end

  describe '.compatible?' do
    subject(:compatible?) { described_class.compatible? }

    context 'when "railties" gem is loaded with a version' do
      context 'that is less than the minimum' do
        include_context 'loaded gems', railties: decrement_gem_version(described_class::MINIMUM_VERSION)
        it { is_expected.to be false }
      end

      context 'that meets the minimum version' do
        include_context 'loaded gems', railties: described_class::MINIMUM_VERSION
        it { is_expected.to be true }
      end
    end

    context 'when "railties" gem and "railties" gem are not loaded' do
      include_context 'loaded gems', railties: nil
      it { is_expected.to be false }
    end
  end

  describe '.patchable?' do
    subject(:patchable?) { described_class.patchable? }

    context 'when available, loaded, and compatible' do
      before do
        allow(described_class).to receive(:available?).and_return(true)
        allow(described_class).to receive(:loaded?).and_return(true)
        allow(described_class).to receive(:compatible?).and_return(true)
      end

      context "and #{Datadog::Tracing::Contrib::Rails::Ext::ENV_DISABLE}" do
        context 'is not set' do
          around do |example|
            ClimateControl.modify Datadog::Tracing::Contrib::Rails::Ext::ENV_DISABLE => nil do
              example.run
            end
          end

          it { is_expected.to be true }
        end

        context 'is set' do
          around do |example|
            ClimateControl.modify Datadog::Tracing::Contrib::Rails::Ext::ENV_DISABLE => '1' do
              example.run
            end
          end

          it { is_expected.to be false }
        end
      end
    end
  end

  describe '#auto_instrument?' do
    subject(:auto_instrument?) { integration.auto_instrument? }

    it { is_expected.to be(true) }
  end

  describe '#default_configuration' do
    subject(:default_configuration) { integration.default_configuration }

    it { is_expected.to be_a_kind_of(Datadog::Tracing::Contrib::Rails::Configuration::Settings) }
  end

  describe '#patcher' do
    subject(:patcher) { integration.patcher }

    it { is_expected.to be Datadog::Tracing::Contrib::Rails::Patcher }
  end
end
