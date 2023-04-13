require 'datadog/tracing/contrib/support/spec_helper'

require 'datadog/tracing/contrib/elasticsearch/integration'

RSpec.describe Datadog::Tracing::Contrib::Elasticsearch::Integration do
  extend ConfigurationHelpers

  let(:integration) { described_class.new(:elasticsearch) }

  describe '.version' do
    subject(:version) { described_class.version }

    context 'when the "elastic-transport" gem is loaded' do
      include_context 'loaded gems', :'elastic-transport' => described_class::MINIMUM_VERSION
      it { is_expected.to be_a_kind_of(Gem::Version) }
    end

    context 'when the "elasticsearch-transport" gem is loaded' do
      include_context 'loaded gems', :'elasticsearch-transport' => described_class::MINIMUM_VERSION
      it { is_expected.to be_a_kind_of(Gem::Version) }
    end

    context 'when "elasticsearch-transport" gem is not loaded' do
      include_context 'loaded gems', :'elasticsearch-transport' => nil, :'elastic-transport' => nil
      it { is_expected.to be nil }
    end
  end

  describe '.loaded?' do
    subject(:loaded?) { described_class.loaded? }

    context 'when Elastic::Transport is defined' do
      before { stub_const('Elastic::Transport', Class.new) }

      it { is_expected.to be true }
    end

    context 'when Elasticsearch::Transport is defined' do
      before { stub_const('Elasticsearch::Transport', Class.new) }

      it { is_expected.to be true }
    end

    context 'when neither Elastic::Transport nor Elasticsearch::Transport are defined' do
      before do
        hide_const('Elastic::Transport')
        hide_const('Elasticsearch::Transport')
      end

      it { is_expected.to be false }
    end
  end

  describe '.compatible?' do
    subject(:compatible?) { described_class.compatible? }

    context 'when "elastic-transport" gem is loaded with a version' do
      context 'that is less than the minimum' do
        include_context 'loaded gems',
          :'elastic-transport' => decrement_gem_version(described_class::MINIMUM_VERSION),
          :'elasticsearch-transport' => nil
        it { is_expected.to be false }
      end

      context 'that meets the minimum version' do
        include_context 'loaded gems',
          :'elastic-transport' => described_class::MINIMUM_VERSION,
          :'elasticsearch-transport' => nil
        it { is_expected.to be true }
      end
    end

    context 'when "elasticsearch-transport" gem is loaded with a version' do
      context 'that is less than the minimum' do
        include_context 'loaded gems',
          :'elastic-transport' => nil,
          :'elasticsearch-transport' => decrement_gem_version(described_class::MINIMUM_VERSION)
        it { is_expected.to be false }
      end

      context 'that meets the minimum version' do
        include_context 'loaded gems',
          :'elastic-transport' => nil,
          :'elasticsearch-transport' => described_class::MINIMUM_VERSION

        it { is_expected.to be true }
      end
    end

    context 'when gem is not loaded' do
      include_context 'loaded gems', :'elastic-transport' => nil, :'elasticsearch-transport' => nil
      it { is_expected.to be false }
    end
  end

  describe '#auto_instrument?' do
    subject(:auto_instrument?) { integration.auto_instrument? }

    it { is_expected.to be(true) }
  end

  describe '#default_configuration' do
    subject(:default_configuration) { integration.default_configuration }

    it { is_expected.to be_a_kind_of(Datadog::Tracing::Contrib::Elasticsearch::Configuration::Settings) }
  end

  describe '#patcher' do
    subject(:patcher) { integration.patcher }

    it { is_expected.to be Datadog::Tracing::Contrib::Elasticsearch::Patcher }
  end
end
