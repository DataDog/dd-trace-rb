require 'spec_helper'

require 'datadog/core/telemetry/schemas/v1/events/app_started'

RSpec.describe Datadog::Core::Telemetry::Schemas::V1::Events::AppStarted do
  describe '#initialize' do
    let(:additional_payload) { [] }
    let(:configuration) { [] }
    let(:dependencies) { [] }
    let(:integrations) { [] }
    context 'given no parameters' do
      subject(:app_started) { described_class.new }
      it { is_expected.to be_a_kind_of(described_class) }
    end

    context 'given all parameters' do
      subject(:app_started) do
        described_class.new(
          additional_payload: additional_payload,
          configuration: configuration,
          dependencies: dependencies,
          integrations: integrations,
        )
      end
      it do
        is_expected.to have_attributes(
          additional_payload: additional_payload,
          configuration: configuration,
          dependencies: dependencies,
          integrations: integrations,
        )
      end
    end
  end
end
