require 'datadog/tracing/contrib/support/spec_helper'

require 'datadog/tracing/contrib/racecar/integration'

RSpec.describe Datadog::Tracing::Contrib::Racecar::Integration do
  extend ConfigurationHelpers

  let(:integration) { described_class.new(:racecar) }

  describe '.version' do
    subject(:version) { described_class.version }

    context 'when the "racecar" gem is loaded' do
      include_context 'loaded gems', racecar: described_class::MINIMUM_VERSION
      it { is_expected.to be_a_kind_of(Gem::Version) }
    end

    context 'when "racecar" gem is not loaded' do
      include_context 'loaded gems', racecar: nil
      it { is_expected.to be nil }
    end
  end

  describe '.loaded?' do
    subject(:loaded?) { described_class.loaded? }

    context 'when neither Racecar or ActiveSupport::Notifications are defined' do
      before do
        hide_const('Racecar')
        hide_const('ActiveSupport::Notifications')
      end

      it { is_expected.to be false }
    end

    context 'when only Racecar is defined' do
      before do
        stub_const('Racecar', Class.new)
        hide_const('ActiveSupport::Notifications')
      end

      it { is_expected.to be false }
    end

    context 'when only ActiveSupport::Notifications is defined' do
      before do
        hide_const('Racecar')
        stub_const('ActiveSupport::Notifications', Class.new)
      end

      it { is_expected.to be false }
    end

    context 'when both Racecar and ActiveSupport::Notifications are defined' do
      before do
        stub_const('Racecar', Class.new)
        stub_const('ActiveSupport::Notifications', Class.new)
      end

      it { is_expected.to be true }
    end
  end

  describe '.compatible?' do
    subject(:compatible?) { described_class.compatible? }

    context 'when "racecar" gem is loaded with a version' do
      context 'that is less than the minimum' do
        include_context 'loaded gems', racecar: decrement_gem_version(described_class::MINIMUM_VERSION)
        it { is_expected.to be false }
      end

      context 'that meets the minimum version' do
        include_context 'loaded gems', racecar: described_class::MINIMUM_VERSION
        it { is_expected.to be true }
      end
    end

    context 'when gem is not loaded' do
      include_context 'loaded gems', racecar: nil
      it { is_expected.to be false }
    end
  end

  describe '#auto_instrument?' do
    subject(:auto_instrument?) { integration.auto_instrument? }

    it { is_expected.to be(true) }
  end

  describe '#default_configuration' do
    subject(:default_configuration) { integration.default_configuration }

    it { is_expected.to be_a_kind_of(Datadog::Tracing::Contrib::Racecar::Configuration::Settings) }
  end

  describe '#patcher' do
    subject(:patcher) { integration.patcher }

    it { is_expected.to be Datadog::Tracing::Contrib::Racecar::Patcher }
  end
end
