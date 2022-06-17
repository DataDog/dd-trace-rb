require 'spec_helper'

require 'datadog/core/telemetry/event'
require 'datadog/core/telemetry/v1/shared_examples'

RSpec.describe Datadog::Core::Telemetry::Event do
  subject(:event) { described_class.new(request_type: request_type, seq_id: seq_id, api_version: api_version) }
  let(:request_type) { 'app-started' }
  let(:seq_id) { 1 }
  let(:api_version) { 'v1' }

  # DD_SERVICE must be set in the application
  around do |example|
    ClimateControl.modify(Datadog::Core::Environment::Ext::ENV_SERVICE => 'env_service') do
      example.run
    end
  end

  describe '#initialize' do
    context ':request_type' do
      it_behaves_like 'a required string parameter', 'request_type'
    end

    context 'when :seq_id' do
      it_behaves_like 'a required int parameter', 'seq_id'
    end

    context ':api_version' do
      it_behaves_like 'a required string parameter', 'api_version'
      context 'defaults to v1 when not provided' do
        subject(:event) { described_class.new(request_type: request_type, seq_id: seq_id) }
        it { is_expected.to have_attributes(api_version: 'v1') }
      end
    end
  end

  describe '#request' do
    subject(:request) { event.request }

    it { is_expected.to be_a_kind_of(Datadog::Core::Telemetry::V1::TelemetryRequest) }
    it { expect(request.api_version).to eql(api_version) }
    it { expect(request.request_type).to eql(request_type) }
    it { expect(request.seq_id).to eql(seq_id) }

    context 'when :request_type' do
      context 'is app-started' do
        let(:request_type) { 'app-started' }

        it { expect(request.payload).to be_a_kind_of(Datadog::Core::Telemetry::V1::AppStarted) }
      end

      context 'is invalid option' do
        let(:request_type) { 'some-request-type' }
        it { expect { request }.to raise_error(ArgumentError) }
      end
    end

    context('when :api_version') do
      context 'is valid version' do
        let(:api_version) { 'v1' }
        it { expect(request.api_version).to eq('v1') }
      end

      context 'is not a valid version' do
        let(:api_version) { 'v2' }
        it { expect { request }.to raise_error(ArgumentError) }
      end
    end
  end
end
