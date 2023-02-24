require 'datadog/tracing/contrib/support/spec_helper'

require 'datadog/tracing/contrib/kafka/integration'

RSpec.describe Datadog::Tracing::Contrib::Kafka::Integration do
  extend ConfigurationHelpers

  let(:integration) { described_class.new(:kafka) }

  describe '.version' do
    subject(:version) { described_class.version }

    context 'when the "ruby-kafka" gem is loaded' do
      include_context 'loaded gems', :'ruby-kafka' => described_class::MINIMUM_VERSION
      it { is_expected.to be_a_kind_of(Gem::Version) }
    end

    context 'when "ruby-kafka" gem is not loaded' do
      include_context 'loaded gems', :'ruby-kafka' => nil
      it { is_expected.to be nil }
    end
  end

  describe '.loaded?' do
    subject(:loaded?) { described_class.loaded? }

    context 'when neither Kafka or ActiveSupport::Notifications are defined' do
      before do
        hide_const('Kafka')
        hide_const('ActiveSupport::Notifications')
      end

      it { is_expected.to be false }
    end

    context 'when only Kafka is defined' do
      before do
        stub_const('Kafka', Class.new)
        hide_const('ActiveSupport::Notifications')
      end

      it { is_expected.to be false }
    end

    context 'when only ActiveSupport::Notifications is defined' do
      before do
        hide_const('Kafka')
        stub_const('ActiveSupport::Notifications', Class.new)
      end

      it { is_expected.to be false }
    end

    context 'when both Kafka and ActiveSupport::Notifications are defined' do
      before do
        stub_const('Kafka', Class.new)
        stub_const('ActiveSupport::Notifications', Class.new)
      end

      it { is_expected.to be true }
    end
  end

  describe '.compatible?' do
    subject(:compatible?) { described_class.compatible? }

    context 'when "ruby-kafka" gem is loaded with a version' do
      context 'that is less than the minimum' do
        include_context 'loaded gems', :'ruby-kafka' => decrement_gem_version(described_class::MINIMUM_VERSION)
        it { is_expected.to be false }
      end

      context 'that meets the minimum version' do
        include_context 'loaded gems', :'ruby-kafka' => described_class::MINIMUM_VERSION
        it { is_expected.to be true }
      end
    end

    context 'when gem is not loaded' do
      include_context 'loaded gems', :'ruby-kafka' => nil
      it { is_expected.to be false }
    end
  end

  describe '#auto_instrument?' do
    subject(:auto_instrument?) { integration.auto_instrument? }

    it { is_expected.to be(true) }
  end

  describe '#default_configuration' do
    subject(:default_configuration) { integration.default_configuration }

    it { is_expected.to be_a_kind_of(Datadog::Tracing::Contrib::Kafka::Configuration::Settings) }
  end

  describe '#patcher' do
    subject(:patcher) { integration.patcher }

    it { is_expected.to be Datadog::Tracing::Contrib::Kafka::Patcher }
  end
end
