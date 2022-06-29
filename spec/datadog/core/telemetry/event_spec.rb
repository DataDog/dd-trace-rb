require 'spec_helper'

require 'datadog/core/telemetry/event'
require 'datadog/core/telemetry/v1/shared_examples'

RSpec.describe Datadog::Core::Telemetry::Event do
  subject(:event) { described_class.new(api_version: api_version) }
  let(:api_version) { 'v1' }

  describe '#initialize' do
    subject(:event) { described_class.new(api_version: api_version) }

    context ':api_version' do
      let(:api_version) { 'v1' }

      context 'when not provided' do
        subject(:event) { described_class.new }
        it { is_expected.to have_attributes(api_version: 'v1') }
      end

      context 'when provided with valid value' do
        let(:api_version) { 'v1' }
        it { is_expected.to have_attributes(api_version: 'v1') }
      end

      context 'when given invalid value' do
        let(:api_version) { 'v2' }
        it { expect { event }.to raise_error(ArgumentError) }
      end
    end
  end

  describe '#telemetry_request' do
    subject(:telemetry_request) { event.telemetry_request(request_type: request_type, seq_id: seq_id) }

    let(:request_type) { 'app-started' }
    let(:seq_id) { 1 }

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

    context 'when :seq_id' do
      context 'is nil' do
        let(:seq_id) { nil }
        it { expect { telemetry_request }.to raise_error(ArgumentError) }
      end

      context 'is valid' do
        let(:seq_id) { 2 }
        it { expect(telemetry_request.payload).to be_a_kind_of(Datadog::Core::Telemetry::V1::AppStarted) }
      end
    end
  end
end
