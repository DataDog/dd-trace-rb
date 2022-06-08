require 'spec_helper'

require 'datadog/core/telemetry/schemas/v1/events/app_started'

RSpec.describe Datadog::Core::Telemetry::Schemas::V1::Events::AppStarted do
  describe '#initialize' do
    let(:configuration) { [] }
    let(:dependencies) { [] }
    let(:integrations) { [] }
    let(:additional_payload) { [] }
    context 'given no parameters' do
      subject(:app_started) { described_class.new }
      it { is_expected.to be_a_kind_of(described_class) }
    end

    context 'given all parameters' do
      subject(:app_started) do
        described_class.new(configuration: configuration, dependencies: dependencies, integrations: integrations,
                            additional_payload: additional_payload)
      end
      it {
        is_expected.to have_attributes(configuration: configuration, dependencies: dependencies, integrations: integrations,
                                       additional_payload: additional_payload)
      }
    end
  end
end
