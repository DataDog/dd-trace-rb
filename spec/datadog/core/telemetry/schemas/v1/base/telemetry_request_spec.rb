require 'spec_helper'

require 'datadog/core/telemetry/schemas/v1/base/telemetry_request'
require 'datadog/core/telemetry/schemas/v1/events/app_started'
require 'datadog/core/telemetry/schemas/v1/base/application'
require 'datadog/core/telemetry/schemas/v1/base/host'
require 'datadog/core/telemetry/schemas/v1/base/integration'
require 'datadog/core/telemetry/schemas/shared_examples'

RSpec.describe Datadog::Core::Telemetry::Schemas::V1::Base::TelemetryRequest do
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

  let(:api_version) { 'v1' }
  let(:application) do
    Datadog::Core::Telemetry::Schemas::V1::Base::Application.new(language_name: 'ruby', language_version: '3.0',
                                                                 service_name: 'myapp', tracer_version: '1.0')
  end
  let(:debug) { false }
  let(:host) { Datadog::Core::Telemetry::Schemas::V1::Base::Host.new(container_id: 'd39b145254d1f9c337fdd2be132f6') }
  let(:payload) do
    Datadog::Core::Telemetry::Schemas::V1::Events::AppStarted.new(
      integrations: [Datadog::Core::Telemetry::Schemas::V1::Base::Integration.new(
        name: 'pg', enabled: true
      )]
    )
  end
  let(:request_type) { 'app-started' }
  let(:runtime_id) { '20338dfd-f700-0d470f054ae8' }
  let(:seq_id) { 42 }
  let(:session_id) { '20338dfd-f700-0d470f054ae8' }
  let(:tracer_time) { 1654805621 }

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

  describe '#initialize' do
    context 'when :api_version' do
      context 'when it is nil' do
        let(:api_version) { nil }
        it { expect { telemetry_request }.to raise_error(ArgumentError) }
      end

      context 'when it is empty string' do
        let(:api_version) { '' }
        it { expect { telemetry_request }.to raise_error(ArgumentError) }
      end

      context 'when it is random valid string' do
        let(:api_version) { 'valid' }
        it { expect { telemetry_request }.to raise_error(ArgumentError) }
      end

      context 'when it is valid api version' do
        let(:api_version) { 'v1' }
        it { is_expected.to be_a_kind_of(described_class) }
      end
    end

    context 'when :application' do
      context 'is nil' do
        let(:application) { nil }
        it { expect { telemetry_request }.to raise_error(ArgumentError) }
      end

      context 'is not of type Application' do
        let(:application) { { container_id: 'd39b145254d1f9c337fdd2be132f6' } }
        it { expect { telemetry_request }.to raise_error(ArgumentError) }
      end

      context 'is valid' do
        let(:host) { Datadog::Core::Telemetry::Schemas::V1::Base::Host.new(container_id: 'd39b145254d1f9c337fdd2be132f6') }
        it { is_expected.to be_a_kind_of(described_class) }
      end
    end

    context 'when :debug' do
      it_behaves_like 'an optional boolean argument', 'debug'
    end

    context 'when :host' do
      context 'is nil' do
        let(:host) { nil }
        it { expect { telemetry_request }.to raise_error(ArgumentError) }
      end

      context 'is not of type Host' do
        let(:host) { { language_name: 'ruby', language_version: '3.0', service_name: 'myapp', tracer_version: '1.0' } }
        it { expect { telemetry_request }.to raise_error(ArgumentError) }
      end

      context 'is valid' do
        let(:application) do
          Datadog::Core::Telemetry::Schemas::V1::Base::Application.new(language_name: 'ruby', language_version: '3.0',
                                                                       service_name: 'myapp', tracer_version: '1.0')
        end
        it { is_expected.to be_a_kind_of(described_class) }
      end
    end

    context 'when :payload' do
      context 'when it is nil' do
        let(:payload) { nil }
        it { expect { telemetry_request }.to raise_error(ArgumentError) }
      end

      context 'is not of type Payload' do
        let(:payload) do
          { integrations: [Datadog::Core::Telemetry::Schemas::V1::Base::Integration.new(name: 'pg', enabled: true)] }
        end
        it { expect { telemetry_request }.to raise_error(ArgumentError) }
      end

      context 'is valid' do
        let(:payload) do
          Datadog::Core::Telemetry::Schemas::V1::Events::AppStarted.new(
            integrations: [Datadog::Core::Telemetry::Schemas::V1::Base::Integration.new(
              name: 'pg', enabled: true
            )]
          )
        end
        it { is_expected.to be_a_kind_of(described_class) }
      end
    end

    context 'when :request_type' do
      context 'when it is nil' do
        let(:request_type) { nil }
        it { expect { telemetry_request }.to raise_error(ArgumentError) }
      end

      context 'when it is empty string' do
        let(:request_type) { '' }
        it { expect { telemetry_request }.to raise_error(ArgumentError) }
      end

      context 'when it is random valid string' do
        let(:request_type) { 'valid' }
        it { expect { telemetry_request }.to raise_error(ArgumentError) }
      end

      context 'when it is valid request type' do
        let(:request_type) { 'app-started' }
        it { is_expected.to be_a_kind_of(described_class) }
      end

      context 'when :runtime_id' do
        it_behaves_like 'a string argument', 'runtime_id'
      end

      context 'when :seq_id' do
        context 'is nil' do
          let(:seq_id) { nil }
          it { expect { telemetry_request }.to raise_error(ArgumentError) }
        end

        context 'is string' do
          let(:seq_id) { '42' }
          it { expect { telemetry_request }.to raise_error(ArgumentError) }
        end

        context 'is valid int' do
          let(:seq_id) { 42 }
          it { is_expected.to be_a_kind_of(described_class) }
        end
      end

      context 'when :session_id' do
        it_behaves_like 'an optional string argument', 'session_id'
      end

      context 'when :tracer_time' do
        context 'is nil' do
          let(:tracer_time) { nil }
          it { expect { telemetry_request }.to raise_error(ArgumentError) }
        end

        context 'is string' do
          let(:tracer_time) { '1654805621' }
          it { expect { telemetry_request }.to raise_error(ArgumentError) }
        end

        context 'is valid int' do
          let(:tracer_time) { 1654805621 }
          it { is_expected.to be_a_kind_of(described_class) }
        end
      end
    end
  end
end
