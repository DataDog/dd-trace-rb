require 'datadog/tracing/contrib/support/spec_helper'

require 'datadog/tracing/contrib/grape/integration'

RSpec.describe Datadog::Tracing::Contrib::Grape::Integration do
  extend ConfigurationHelpers

  let(:integration) { described_class.new(:grape) }

  describe '.version' do
    subject(:version) { described_class.version }

    context 'when the "grape" gem is loaded' do
      include_context 'loaded gems', grape: described_class::MINIMUM_VERSION
      it { is_expected.to be_a_kind_of(Gem::Version) }
    end

    context 'when "grape" gem is not loaded' do
      include_context 'loaded gems', grape: nil
      it { is_expected.to be nil }
    end
  end

  describe '.loaded?' do
    subject(:loaded?) { described_class.loaded? }

    context 'when neither Grape or ActiveSupport::Notifications are defined' do
      before do
        hide_const('Grape')
        hide_const('ActiveSupport::Notifications')
      end

      it { is_expected.to be false }
    end

    context 'when only Grape is defined' do
      before do
        stub_const('Grape', Class.new)
        hide_const('ActiveSupport::Notifications')
      end

      it { is_expected.to be false }
    end

    context 'when only ActiveSupport::Notifications is defined' do
      before do
        hide_const('Grape')
        stub_const('ActiveSupport::Notifications', Class.new)
      end

      it { is_expected.to be false }
    end

    context 'when both Grape and ActiveSupport::Notifications are defined' do
      before do
        stub_const('Grape', Class.new)
        stub_const('ActiveSupport::Notifications', Class.new)
      end

      it { is_expected.to be true }
    end
  end

  describe '.compatible?' do
    subject(:compatible?) { described_class.compatible? }

    context 'when "grape" gem is loaded with a version' do
      context 'that is less than the minimum' do
        include_context 'loaded gems', grape: decrement_gem_version(described_class::MINIMUM_VERSION)
        it { is_expected.to be false }
      end

      context 'that meets the minimum version' do
        include_context 'loaded gems', grape: described_class::MINIMUM_VERSION
        it { is_expected.to be true }
      end
    end

    context 'when gem is not loaded' do
      include_context 'loaded gems', grape: nil
      it { is_expected.to be false }
    end
  end

  describe '#auto_instrument?' do
    subject(:auto_instrument?) { integration.auto_instrument? }

    it { is_expected.to be(true) }
  end

  describe '#default_configuration' do
    subject(:default_configuration) { integration.default_configuration }

    it { is_expected.to be_a_kind_of(Datadog::Tracing::Contrib::Grape::Configuration::Settings) }
  end

  describe '#patcher' do
    subject(:patcher) { integration.patcher }

    it { is_expected.to be Datadog::Tracing::Contrib::Grape::Patcher }
  end
end
