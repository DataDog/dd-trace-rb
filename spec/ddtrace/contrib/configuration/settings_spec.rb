require 'spec_helper'

require 'ddtrace'

RSpec.describe Datadog::Contrib::Configuration::Settings do
  subject(:settings) { described_class.new }

  it { is_expected.to be_a_kind_of(Datadog::Configuration::Options) }

  describe '#to_h' do
    subject(:hash) { settings.to_h }
    let(:options_hash) { { option: true } }
    let(:integrations_hash) { { integration: true } }

    before do
      allow(settings).to receive(:options_hash)
        .and_return(options_hash)

      allow(settings).to receive(:integrations_hash)
        .and_return(integrations_hash)
    end

    it do
      is_expected.to eq(integrations_hash.merge(options_hash))
      expect(settings).to have_received(:options_hash)
      expect(settings).to have_received(:integrations_hash)
    end
  end

  describe '#reset!' do
    subject(:reset!) { settings.reset! }

    before do
      allow(settings).to receive(:reset_options!)
      allow(settings).to receive(:reset_integrations!)
      reset!
    end

    it 'resets the options' do
      expect(settings).to have_received(:reset_options!)
      expect(settings).to have_received(:reset_integrations!)
    end
  end

  describe '#options' do
    subject(:options) { settings.options }

    describe ':service_name' do
      subject(:option) { options[:service_name] }
      it { expect(options).to include(:service_name) }
      it { expect(option.get).to be nil }
    end

    describe ':tracer' do
      subject(:option) { options[:tracer] }
      it { expect(options).to include(:tracer) }
      it { expect(option.get).to be Datadog.tracer }
    end

    describe ':analytics_enabled' do
      subject(:option) { options[:analytics_enabled] }
      it { expect(options).to include(:analytics_enabled) }
      it { expect(option.get).to be false }
    end

    describe ':analytics_sample_rate' do
      subject(:option) { options[:analytics_sample_rate] }
      it { expect(options).to include(:analytics_sample_rate) }
      it { expect(option.get).to eq 1.0 }
    end
  end
end
