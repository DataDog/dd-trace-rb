require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/auto_instrument_examples'

require 'datadog/tracing/contrib/view_component/integration'

RSpec.describe Datadog::Tracing::Contrib::ViewComponent::Integration do
  let(:integration) { described_class.new(:view_component) }

  describe '.version' do
    subject(:version) { described_class.version }

    context 'when the "view_component" gem is loaded' do
      include_context 'loaded gems', view_component: described_class::MINIMUM_VERSION
      it { is_expected.to be_a_kind_of(Gem::Version) }
    end
  end

  describe '.loaded?' do
    subject(:loaded?) { described_class.loaded? }

    context 'when ViewComponent is defined' do
      before { stub_const('ViewComponent', Class.new) }

      it { is_expected.to be true }
    end

    context 'when ViewComponent is not defined' do
      before { hide_const('ViewComponent') }

      it { is_expected.to be false }
    end
  end

  describe '.compatible?' do
    subject(:compatible?) { described_class.compatible? }

    context 'when "view_component" gem is loaded with a version' do
      context 'that is less than the minimum' do
        include_context 'loaded gems', view_component: decrement_gem_version(described_class::MINIMUM_VERSION)
        it { is_expected.to be false }
      end

      context 'that meets the minimum version' do
        include_context 'loaded gems', view_component: described_class::MINIMUM_VERSION
        it { is_expected.to be true }
      end
    end

    context 'when gem is not loaded' do
      include_context 'loaded gems', actionpack: nil, view_component: nil
      it { is_expected.to be false }
    end
  end

  describe '#default_configuration' do
    subject(:default_configuration) { integration.default_configuration }

    it { is_expected.to be_a_kind_of(Datadog::Tracing::Contrib::ViewComponent::Configuration::Settings) }
  end

  describe '#patcher' do
    subject(:patcher) { integration.patcher }

    it { is_expected.to be Datadog::Tracing::Contrib::ViewComponent::Patcher }
  end
end
