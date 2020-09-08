require 'ddtrace/contrib/support/spec_helper'

require 'ddtrace/contrib/resque/integration'

RSpec.describe Datadog::Contrib::Resque::Integration do
  extend ConfigurationHelpers

  let(:integration) { described_class.new(:resque) }

  describe '.version' do
    subject(:version) { described_class.version }

    context 'when the "resque" gem is loaded' do
      include_context 'loaded gems', resque: described_class::MINIMUM_VERSION
      it { is_expected.to be_a_kind_of(Gem::Version) }
    end

    context 'when "resque" gem is not loaded' do
      include_context 'loaded gems', resque: nil
      it { is_expected.to be nil }
    end
  end

  describe '.loaded?' do
    subject(:loaded?) { described_class.loaded? }

    context 'when Resque is defined' do
      before { stub_const('Resque', Class.new) }
      it { is_expected.to be true }
    end

    context 'when Resque is not defined' do
      before { hide_const('Resque') }
      it { is_expected.to be false }
    end
  end

  describe '.compatible?' do
    subject(:compatible?) { described_class.compatible? }

    context 'when "resque" gem is loaded with a version' do
      context 'that is less than the minimum' do
        include_context 'loaded gems', resque: decrement_gem_version(described_class::MINIMUM_VERSION)
        it { is_expected.to be false }
      end

      context 'that meets the minimum version' do
        include_context 'loaded gems', resque: described_class::MINIMUM_VERSION
        it { is_expected.to be true }
      end

      context 'that exceeds the maximum version' do
        include_context 'loaded gems', resque: described_class::MAXIMUM_VERSION
        it { is_expected.to be false }
      end
    end

    context 'when gem is not loaded' do
      include_context 'loaded gems', resque: nil
      it { is_expected.to be false }
    end
  end

  describe '.sync_writer' do
    it { expect(described_class).to respond_to(:sync_writer) }
    it { expect(described_class).to respond_to(:sync_writer=) }
  end

  describe '#default_configuration' do
    subject(:default_configuration) { integration.default_configuration }
    it { is_expected.to be_a_kind_of(Datadog::Contrib::Resque::Configuration::Settings) }
  end

  describe '#patcher' do
    subject(:patcher) { integration.patcher }
    it { is_expected.to be Datadog::Contrib::Resque::Patcher }
  end
end
