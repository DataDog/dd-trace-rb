require 'ddtrace/contrib/support/spec_helper'

require 'ddtrace/contrib/elasticsearch/integration'

RSpec.describe Datadog::Contrib::Elasticsearch::Integration do
  extend ConfigurationHelpers

  let(:integration) { described_class.new(:elasticsearch) }

  describe '.version' do
    subject(:version) { described_class.version }

    context 'when the "elasticsearch-transport" gem is loaded' do
      include_context 'loaded gems', :'elasticsearch-transport' => described_class::MINIMUM_VERSION
      it { is_expected.to be_a_kind_of(Gem::Version) }
    end

    context 'when "elasticsearch-transport" gem is not loaded' do
      include_context 'loaded gems', :'elasticsearch-transport' => nil
      it { is_expected.to be nil }
    end
  end

  describe '.loaded?' do
    subject(:loaded?) { described_class.loaded? }

    context 'when Elasticsearch::Transport is defined' do
      before { stub_const('Elasticsearch::Transport', Class.new) }
      it { is_expected.to be true }
    end

    context 'when Elasticsearch::Transport is not defined' do
      before { hide_const('Elasticsearch::Transport') }
      it { is_expected.to be false }
    end
  end

  describe '.compatible?' do
    subject(:compatible?) { described_class.compatible? }

    context 'when "elasticsearch-transport" gem is loaded with a version' do
      context 'that is less than the minimum' do
        include_context 'loaded gems', :'elasticsearch-transport' => decrement_gem_version(described_class::MINIMUM_VERSION)
        it { is_expected.to be false }
      end

      context 'that meets the minimum version' do
        include_context 'loaded gems', :'elasticsearch-transport' => described_class::MINIMUM_VERSION
        it { is_expected.to be true }
      end
    end

    context 'when gem is not loaded' do
      include_context 'loaded gems', :'elasticsearch-transport' => nil
      it { is_expected.to be false }
    end
  end

  describe '#default_configuration' do
    subject(:default_configuration) { integration.default_configuration }
    it { is_expected.to be_a_kind_of(Datadog::Contrib::Elasticsearch::Configuration::Settings) }
  end

  describe '#patcher' do
    subject(:patcher) { integration.patcher }
    it { is_expected.to be Datadog::Contrib::Elasticsearch::Patcher }
  end
end
