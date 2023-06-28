require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/action_mailer/integration'

RSpec.describe Datadog::Tracing::Contrib::ActionMailer::Integration do
  extend ConfigurationHelpers

  let(:integration) { described_class.new(:action_mailer) }

  describe '.version' do
    subject(:version) { described_class.version }

    context 'when the "actionmailer" gem is loaded' do
      include_context 'loaded gems', actionmailer: described_class::MINIMUM_VERSION
      it { is_expected.to be_a_kind_of(Gem::Version) }
    end

    context 'when "actionmailer" gem is not loaded' do
      include_context 'loaded gems', actionmailer: nil
      it { is_expected.to be nil }
    end
  end

  describe '.loaded?' do
    subject(:loaded?) { described_class.loaded? }

    context 'when ActionMailer is defined' do
      before { stub_const('ActionMailer', Class.new) }
      it { is_expected.to be true }
    end

    context 'when ActionMailer is not defined' do
      before { hide_const('ActionMailer') }
      it { is_expected.to be false }
    end
  end

  describe '.compatible?' do
    subject(:compatible?) { described_class.compatible? }

    context 'when "actionmailer" gem is loaded with a version' do
      context 'that is less than the minimum' do
        include_context 'loaded gems', actionmailer: decrement_gem_version(described_class::MINIMUM_VERSION)
        it { is_expected.to be false }
      end

      context 'that meets the minimum version' do
        include_context 'loaded gems', actionmailer: described_class::MINIMUM_VERSION
        it { is_expected.to be true }
      end
    end

    context 'when gem is not loaded' do
      include_context 'loaded gems', actionmailer: nil
      it { is_expected.to be false }
    end
  end

  describe '#default_configuration' do
    subject(:default_configuration) { integration.default_configuration }
    it { is_expected.to be_a_kind_of(Datadog::Tracing::Contrib::ActionMailer::Configuration::Settings) }
  end

  describe '#patcher' do
    subject(:patcher) { integration.patcher }
    it { is_expected.to be Datadog::Tracing::Contrib::ActionMailer::Patcher }
  end
end
