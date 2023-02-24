require 'datadog/tracing/contrib/support/spec_helper'

require 'datadog/tracing/contrib/delayed_job/integration'

RSpec.describe Datadog::Tracing::Contrib::DelayedJob::Integration do
  extend ConfigurationHelpers

  let(:integration) { described_class.new(:delayed_job) }

  describe '.version' do
    subject(:version) { described_class.version }

    context 'when the "delayed_job" gem is loaded' do
      include_context 'loaded gems', delayed_job: described_class::MINIMUM_VERSION
      it { is_expected.to be_a_kind_of(Gem::Version) }
    end

    context 'when "delayed_job" gem is not loaded' do
      include_context 'loaded gems', delayed_job: nil
      it { is_expected.to be nil }
    end
  end

  describe '.loaded?' do
    subject(:loaded?) { described_class.loaded? }

    context 'when Delayed is defined' do
      before { stub_const('Delayed', Class.new) }

      it { is_expected.to be true }
    end

    context 'when Delayed is not defined' do
      before { hide_const('Delayed') }

      it { is_expected.to be false }
    end
  end

  describe '.compatible?' do
    subject(:compatible?) { described_class.compatible? }

    context 'when "delayed_job" gem is loaded with a version' do
      context 'that is less than the minimum' do
        include_context 'loaded gems', delayed_job: decrement_gem_version(described_class::MINIMUM_VERSION)
        it { is_expected.to be false }
      end

      context 'that meets the minimum version' do
        include_context 'loaded gems', delayed_job: described_class::MINIMUM_VERSION
        it { is_expected.to be true }
      end
    end

    context 'when gem is not loaded' do
      include_context 'loaded gems', delayed_job: nil
      it { is_expected.to be false }
    end
  end

  describe '#auto_instrument?' do
    subject(:auto_instrument?) { integration.auto_instrument? }

    it { is_expected.to be(true) }
  end

  describe '#default_configuration' do
    subject(:default_configuration) { integration.default_configuration }

    it { is_expected.to be_a_kind_of(Datadog::Tracing::Contrib::DelayedJob::Configuration::Settings) }
  end

  describe '#patcher' do
    subject(:patcher) { integration.patcher }

    it { is_expected.to be Datadog::Tracing::Contrib::DelayedJob::Patcher }
  end
end
