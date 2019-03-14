require 'spec_helper'

RSpec.describe Datadog do
  describe 'class' do
    subject(:datadog) { described_class }

    describe 'behavior' do
      describe '#tracer' do
        subject { datadog.tracer }
        it { is_expected.to be_an_instance_of(Datadog::Tracer) }
      end

      describe '#registry' do
        subject { datadog.registry }
        it { is_expected.to be_an_instance_of(Datadog::Contrib::Registry) }
      end

      describe '#configuration' do
        subject { datadog.configuration }
        it { is_expected.to be_an_instance_of(Datadog::Configuration::Settings) }
      end

      describe '#configure' do
        let(:configuration) { datadog.configuration }
        it { expect { |b| datadog.configure(&b) }.to yield_with_args(configuration) }
      end
    end
  end
end
