require 'spec_helper'

require 'datadog/core/telemetry/collector'
require 'datadog/core/telemetry/schemas/v1/base/integration'
require 'ddtrace'
require 'rake'

RSpec.describe Datadog::Core::Telemetry::Collector do
  describe '.dependencies' do
    subject(:dependencies) { described_class.dependencies }

    it 'returns an array' do
      is_expected.to be_a(Array)
    end

    it 'returns an array of Dependency objects' do
      is_expected.to all(be_a(Datadog::Core::Telemetry::Schemas::V1::Base::Dependency))
    end
  end

  describe '.integrations' do
    subject(:integrations) { described_class.integrations }

    it 'returns an array' do
      is_expected.to be_a(Array)
    end

    context 'no configuration call is made' do
      it 'returns and empty array' do
        is_expected.to eq([])
      end
    end

    context 'after a configure block is called' do
      around do |example|
        Datadog.registry[:rake].reset_configuration!
        Datadog.registry[:pg].reset_configuration!
        example.run
        Datadog.registry[:rake].reset_configuration!
        Datadog.registry[:pg].reset_configuration!
      end
      before do
        Datadog.configure do |c|
          c.tracing.instrument :rake
          c.tracing.instrument :pg
        end
      end
      it 'creates a list of integrations' do
        expect(integrations.length).to eq(2)
        expect(integrations[0]).to be_a(Datadog::Core::Telemetry::Schemas::V1::Base::Integration)
        expect(integrations[1]).to be_a(Datadog::Core::Telemetry::Schemas::V1::Base::Integration)
        expect(integrations[0]).to have_attributes(name: :rake, enabled: true, compatible: true, error: nil)
      end

      it 'propogates errors with integration configuration' do
        expect(integrations[1])
          .to have_attributes(name: :pg, enabled: false, compatible: false,
                              error: 'Available?: false, Loaded? false, Compatible? false, Patchable? false')
      end
    end
  end
end
