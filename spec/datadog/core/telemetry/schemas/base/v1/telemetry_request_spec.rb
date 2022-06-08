require 'spec_helper'

require 'datadog/core/telemetry/schemas/v1/base/telemetry_request'

RSpec.describe Datadog::Core::Telemetry::Schemas::V1::Base::TelemetryRequest do
  describe '#initialize' do
    let(:api_version) { 'v1' }
    let(:application) { {} }
    let(:debug) { false }
    let(:host) { {} }
    let(:payload) { {} }
    let(:request_type) { 'app-started' }
    let(:runtime_id) { '20338dfd-f700-4e5c-b3f6-0d470f054ae8' }
    let(:seq_id) { 42 }
    let(:session_id) { '20338dfd-f700-4e5c-b3f6-0d470f054ae8' }
    let(:tracer_time) { 'abb6b7ee58bf4d44d6f41c57db' }

    context 'given only required parameters' do
      subject(:telemetry_request) do
        described_class.new(
          application: application,
          host: host,
          payload: payload,
          seq_id: seq_id,
          tracer_time: tracer_time,
          api_version: api_version,
          request_type: request_type,
          runtime_id: runtime_id
        )
      end
      it { is_expected.to be_a_kind_of(described_class) }

      it do
        is_expected.to have_attributes(
          api_version: api_version,
          application: application,
          host: host,
          payload: payload,
          request_type: request_type,
          runtime_id: runtime_id,
          seq_id: seq_id,
          tracer_time: tracer_time
        )
      end

      it { is_expected.to have_attributes(session_id: nil, debug: nil) }
    end

    context 'given all parameters' do
      subject(:telemetry_request) do
        described_class.new(
          api_version: api_version,
          application: application,
          debug: debug,
          host: host,
          payload: payload,
          request_type: request_type,
          runtime_id: runtime_id,
          seq_id: seq_id,
          session_id: session_id,
          tracer_time: tracer_time
        )
      end
      it do
        is_expected.to have_attributes(
          api_version: api_version,
          application: application,
          debug: debug,
          host: host,
          payload: payload,
          request_type: request_type,
          runtime_id: runtime_id,
          seq_id: seq_id,
          session_id: session_id,
          tracer_time: tracer_time
        )
      end
    end
  end
end
