require 'spec_helper'

require 'datadog/core/telemetry/schemas/v1/base/telemetry_request'

RSpec.describe Datadog::Core::Telemetry::Schemas::V1::Base::TelemetryRequest do
  describe '#initialize' do
    let(:api_version) { 'v1' }
    let(:request_type) { 'app-started' }
    let(:runtime_id) { '20338dfd-f700-4e5c-b3f6-0d470f054ae8' }
    let(:tracer_time) { 'abb6b7ee58bf4d44d6f41c57db' }
    let(:seq_id) { 42 }
    let(:payload) { {} }
    let(:application) { {} }
    let(:host) { {} }
    let(:session_id) { '20338dfd-f700-4e5c-b3f6-0d470f054ae8' }
    let(:debug) { false }

    context 'given only required parameters' do
      subject(:telemetry_request) do
        described_class.new(api_version: api_version, request_type: request_type, runtime_id: runtime_id, seq_id: seq_id,
                            tracer_time: tracer_time, payload: payload, application: application, host: host)
      end
      it { is_expected.to be_a_kind_of(described_class) }

      it {
        is_expected
          .to have_attributes(api_version: api_version, request_type: request_type, runtime_id: runtime_id, seq_id: seq_id,
                              tracer_time: tracer_time, payload: payload, application: application, host: host)
      }

      it { is_expected.to have_attributes(session_id: nil, debug: nil) }
    end

    context 'given all parameters' do
      subject(:telemetry_request) do
        described_class.new(api_version: api_version, request_type: request_type, runtime_id: runtime_id, host: host,
                            tracer_time: tracer_time, seq_id: seq_id, payload: payload, application: application,
                            session_id: session_id, debug: debug)
      end
      it {
        is_expected
          .to have_attributes(api_version: api_version, request_type: request_type, runtime_id: runtime_id, host: host,
                              tracer_time: tracer_time, seq_id: seq_id, payload: payload, application: application,
                              session_id: session_id, debug: debug)
      }
    end
  end
end
