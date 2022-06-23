require 'spec_helper'

require 'datadog/core/telemetry/event'
require 'datadog/core/telemetry/v1/shared_examples'

RSpec.describe Datadog::Core::Telemetry::Event do
  subject(:event) { described_class.new(api_version: api_version) }
  let(:api_version) { 'v1' }

  # DD_SERVICE must be set in the application
  around do |example|
    ClimateControl.modify(Datadog::Core::Environment::Ext::ENV_SERVICE => 'env_service') do
      example.run
    end
  end

  describe '#initialize' do
    context ':api_version' do
      it_behaves_like 'a required string parameter', 'api_version'
      context 'defaults to v1 when not provided' do
        subject(:event) { described_class.new }
        it { is_expected.to have_attributes(api_version: 'v1') }
      end
    end
  end

  describe '#telemetry_request' do
    subject(:telemetry_request) { event.telemetry_request(request_type: request_type) }

    let(:request_type) { 'app-started' }

    it { is_expected.to be_a_kind_of(Datadog::Core::Telemetry::V1::TelemetryRequest) }
    it { expect(telemetry_request.api_version).to eql(api_version) }
    it { expect(telemetry_request.request_type).to eql(request_type) }
    it { expect(telemetry_request.seq_id).to be(1) }

    context 'when :request_type' do
      context 'is app-started' do
        let(:request_type) { 'app-started' }

        it { expect(telemetry_request.payload).to be_a_kind_of(Datadog::Core::Telemetry::V1::AppStarted) }
      end

      context 'is nil' do
        let(:request_type) { nil }
        it { expect { telemetry_request }.to raise_error(ArgumentError) }
      end

      context 'is empty string' do
        let(:request_type) { '' }
        it { expect { telemetry_request }.to raise_error(ArgumentError) }
      end

      context 'is invalid option' do
        let(:request_type) { 'some-request-type' }
        it { expect { telemetry_request }.to raise_error(ArgumentError) }
      end
    end

    context('when :api_version') do
      context 'is nil' do
        let(:api_version) { nil }
        it { expect { telemetry_request }.to raise_error(ArgumentError) }
      end

      context 'is valid version' do
        let(:api_version) { 'v1' }
        it { expect(telemetry_request.api_version).to eq('v1') }
      end
    end
  end
end
