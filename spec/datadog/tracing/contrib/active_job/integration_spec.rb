require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/auto_instrument_examples'

require 'datadog/tracing/contrib/active_job/integration'

RSpec.describe Datadog::Tracing::Contrib::ActiveJob::Integration do
  extend ConfigurationHelpers

  let(:integration) { described_class.new(:active_job) }

  describe '.version' do
    subject(:version) { described_class.version }

    context 'when the "activejob" gem is loaded' do
      include_context 'loaded gems', activejob: described_class::MINIMUM_VERSION
      it { is_expected.to be_a_kind_of(Gem::Version) }
    end

    context 'when "activejob" gem is not loaded' do
      include_context 'loaded gems', activejob: nil
      it { is_expected.to be nil }
    end
  end

  describe '.loaded?' do
    subject(:loaded?) { described_class.loaded? }

    context 'when ActiveJob is defined' do
      before { stub_const('ActiveJob', Class.new) }

      it { is_expected.to be true }
    end

    context 'when ActiveJob is not defined' do
      before { hide_const('ActiveJob') }

      it { is_expected.to be false }
    end
  end

  describe '.compatible?' do
    subject(:compatible?) { described_class.compatible? }

    context 'when "activejob" gem is loaded with a version' do
      context 'that is less than the minimum' do
        include_context 'loaded gems', activejob: decrement_gem_version(described_class::MINIMUM_VERSION)
        it { is_expected.to be false }
      end

      context 'that meets the minimum version' do
        include_context 'loaded gems', activejob: described_class::MINIMUM_VERSION
        it { is_expected.to be true }
      end
    end

    context 'when gem is not loaded' do
      include_context 'loaded gems', actionpack: nil, activejob: nil
      it { is_expected.to be false }
    end
  end

  describe '#auto_instrument?' do
    it_behaves_like 'rails sub-gem auto_instrument?'
  end

  describe '#default_configuration' do
    subject(:default_configuration) { integration.default_configuration }

    it { is_expected.to be_a_kind_of(Datadog::Tracing::Contrib::ActiveJob::Configuration::Settings) }
  end

  describe '#patcher' do
    subject(:patcher) { integration.patcher }

    it { is_expected.to be Datadog::Tracing::Contrib::ActiveJob::Patcher }
  end
end
