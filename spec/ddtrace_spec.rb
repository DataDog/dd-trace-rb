# typed: false
require 'spec_helper'

RSpec.describe Datadog do
  describe 'class' do
    subject(:datadog) { described_class }

    describe 'behavior' do
      describe '#tracer' do
        subject(:tracer) { datadog.tracer }

        it { is_expected.to be_an_instance_of(Datadog::Tracer) }
      end

      describe '#configuration' do
        subject(:configuration) { datadog.configuration }

        it do
          is_expected.to be_an_instance_of(Datadog::Configuration::ValidationProxy::Global)
          expect(configuration.send(:settings)).to be_an_instance_of(Datadog::Configuration::Settings)
        end
      end

      describe '#configure' do
        let(:configuration) { datadog.configuration }

        it do
          expect { |b| datadog.configure(&b) }
            .to yield_with_args(kind_of(Datadog::Configuration::ValidationProxy::Global))
        end
      end
    end
  end
end
