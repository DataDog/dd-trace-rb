require 'spec_helper'

require 'ddtrace'

RSpec.describe Datadog::Contrib::Configuration::Settings do
  subject(:settings) { described_class.new }

  it { is_expected.to be_a_kind_of(Datadog::Configuration::Options) }

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
