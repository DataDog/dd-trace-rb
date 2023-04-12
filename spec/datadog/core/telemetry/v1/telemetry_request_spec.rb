require 'spec_helper'

require 'datadog/core/telemetry/v1/telemetry_request'
require 'datadog/core/telemetry/v1/app_event'
require 'datadog/core/telemetry/v1/application'
require 'datadog/core/telemetry/v1/host'
require 'datadog/core/telemetry/v1/integration'
require 'datadog/core/telemetry/v1/shared_examples'

RSpec.describe Datadog::Core::Telemetry::V1::TelemetryRequest do
  subject(:telemetry_request) do
    described_class.new(
      api_version: api_version,
      application: application,
      debug: debug,
      host: host,
      payload: payload,
      request_type: request_type,
      runtime_id: dummy_runtime_id,
      seq_id: seq_id,
      session_id: dummy_session_id,
      tracer_time: tracer_time
    )
  end

  let(:api_version) { 'v1' }
  let(:application) do
    Datadog::Core::Telemetry::V1::Application.new(
      language_name: 'ruby',
      language_version: '3.0',
      service_name: 'myapp',
      tracer_version: '1.0'
    )
  end
  let(:debug) { false }
  let(:host) { Datadog::Core::Telemetry::V1::Host.new(container_id: 'd39b145254d1f9c337fdd2be132f6') }
  let(:payload) do
    Datadog::Core::Telemetry::V1::AppEvent.new(
      integrations: [Datadog::Core::Telemetry::V1::Integration.new(
        name: 'pg', enabled: true
      )]
    )
  end
  let(:request_type) { :'app-started' }
  let(:dummy_runtime_id) { 'dummy_runtime_id' }
  let(:seq_id) { 42 }
  let(:dummy_session_id) { 'dummy_session_id' }
  let(:tracer_time) { 1654805621 }

  it do
    is_expected.to have_attributes(
      api_version: api_version,
      application: application,
      debug: debug,
      host: host,
      payload: payload,
      request_type: request_type,
      runtime_id: dummy_runtime_id,
      seq_id: seq_id,
      session_id: dummy_session_id,
      tracer_time: tracer_time
    )
  end

  describe '#initialize' do
    context 'when :api_version' do
      context 'is nil' do
        let(:api_version) { nil }
        it { expect { telemetry_request }.to raise_error(ArgumentError) }
      end

      context 'is string' do
        let(:api_version) { 'v1' }
        it { is_expected.to be_a_kind_of(described_class) }
      end
    end

    context 'when :application' do
      context 'is nil' do
        let(:application) { nil }
        it { expect { telemetry_request }.to raise_error(ArgumentError) }
      end

      context 'is valid' do
        let(:host) { Datadog::Core::Telemetry::V1::Host.new(container_id: 'd39b145254d1f9c337fdd2be132f6') }
        it { is_expected.to be_a_kind_of(described_class) }
      end
    end

    context ':debug' do
      it_behaves_like 'an optional boolean parameter', 'debug'
    end

    context 'when :host' do
      context 'is nil' do
        let(:host) { nil }
        it { expect { telemetry_request }.to raise_error(ArgumentError) }
      end

      context 'is valid' do
        let(:application) do
          Datadog::Core::Telemetry::V1::Application.new(
            language_name: 'ruby',
            language_version: '3.0',
            service_name: 'myapp',
            tracer_version: '1.0'
          )
        end
        it { is_expected.to be_a_kind_of(described_class) }
      end
    end

    context 'when :payload' do
      context 'is nil' do
        let(:payload) { nil }
        it { expect { telemetry_request }.to raise_error(ArgumentError) }
      end

      context 'is valid' do
        let(:payload) do
          Datadog::Core::Telemetry::V1::AppEvent.new(
            integrations: [Datadog::Core::Telemetry::V1::Integration.new(
              name: 'pg', enabled: true
            )]
          )
        end
        it { is_expected.to be_a_kind_of(described_class) }
      end
    end

    context 'when :request_type' do
      context 'is nil' do
        let(:request_type) { nil }
        it { expect { telemetry_request }.to raise_error(ArgumentError) }
      end

      context 'is valid string' do
        let(:request_type) { :'app-started' }
        it { is_expected.to be_a_kind_of(described_class) }
      end
    end

    context ':runtime_id' do
      it_behaves_like 'a required string parameter', 'dummy_runtime_id'
    end

    context 'when :seq_id' do
      context 'is nil' do
        let(:seq_id) { nil }
        it { expect { telemetry_request }.to raise_error(ArgumentError) }
      end

      context 'is valid int' do
        let(:seq_id) { 42 }
        it { is_expected.to be_a_kind_of(described_class) }
      end
    end

    context ':session_id' do
      it_behaves_like 'an optional string parameter', 'dummy_session_id'
    end

    context 'when :tracer_time' do
      context 'is nil' do
        let(:tracer_time) { nil }
        it { expect { telemetry_request }.to raise_error(ArgumentError) }
      end

      context 'is valid int' do
        let(:tracer_time) { 1654805621 }
        it { is_expected.to be_a_kind_of(described_class) }
      end
    end
  end

  describe '#to_h' do
    subject(:to_h) { telemetry_request.to_h }

    let(:api_version) { 'v1' }
    let(:application) do
      Datadog::Core::Telemetry::V1::Application.new(
        language_name: 'ruby',
        language_version: '3.0',
        service_name: 'myapp',
        tracer_version: '1.0'
      )
    end
    let(:debug) { false }
    let(:host) { Datadog::Core::Telemetry::V1::Host.new(container_id: 'd39b145254d1f9c337fdd2be132f6') }
    let(:payload) do
      Datadog::Core::Telemetry::V1::AppEvent.new(
        integrations: [Datadog::Core::Telemetry::V1::Integration.new(
          name: 'pg', enabled: true
        )]
      )
    end
    let(:request_type) { :'app-started' }
    let(:dummy_runtime_id) { 'dummy_runtime_id' }
    let(:seq_id) { 42 }
    let(:dummy_session_id) { 'dummy_session_id' }
    let(:tracer_time) { 1654805621 }

    it do
      is_expected.to eq(
        api_version: api_version,
        application: {
          language_name: 'ruby',
          language_version: '3.0',
          products: {},
          service_name: 'myapp',
          tracer_version: '1.0'
        },
        debug: debug,
        host: {
          container_id: 'd39b145254d1f9c337fdd2be132f6',
        },
        payload: {
          integrations: [{ enabled: true, name: 'pg' }]
        },
        request_type: request_type,
        runtime_id: dummy_runtime_id,
        seq_id: seq_id,
        session_id: dummy_session_id,
        tracer_time: tracer_time,
      )
    end
  end
end
