require 'spec_helper'

require 'datadog/core/telemetry/schemas/events/v1/app_started'

RSpec.describe Datadog::Core::Telemetry::Schemas::Events::V1::AppStarted do
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
      subject(:app_started) { described_class.new(configuration, dependencies, integrations, additional_payload) }
      it {
        is_expected.to have_attributes(configuration: configuration, dependencies: dependencies, integrations: integrations,
                                       additional_payload: additional_payload)
      }
    end
  end
end
