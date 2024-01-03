require 'spec_helper'

require 'datadog/core/telemetry/v1/app_event'
require 'datadog/core/telemetry/v1/dependency'
require 'datadog/core/telemetry/v1/integration'

RSpec.describe Datadog::Core::Telemetry::V1::AppEvent do
  subject(:app_started) do
    described_class.new(
      additional_payload: additional_payload,
      configuration: configuration,
      dependencies: dependencies,
      install_signature: install_signature,
      integrations: integrations,
    )
  end

  let(:additional_payload) { [{ name: 'logger.level', value: 1 }] }
  let(:configuration) { [{ name: 'DD_TRACE_DEBUG', value: false }] }
  let(:dependencies) { [Datadog::Core::Telemetry::V1::Dependency.new(name: 'pg')] }
  let(:install_signature) do
    Datadog::Core::Telemetry::V1::InstallSignature.new(
      install_id: '123',
      install_type: 'docker',
      install_time: '1703188212'
    )
  end
  let(:integrations) { [Datadog::Core::Telemetry::V1::Integration.new(name: 'pg', enabled: true)] }

  it do
    is_expected.to have_attributes(
      additional_payload: additional_payload,
      configuration: configuration,
      dependencies: dependencies,
      install_signature: install_signature,
      integrations: integrations,
    )
  end

  describe '#initialize' do
    context 'when :additional_payload' do
      context 'is nil' do
        let(:additional_payload) { nil }
        it { is_expected.to be_a_kind_of(described_class) }
      end

      context 'is array of one Hash' do
        let(:additional_payload) { [{ name: 'logger.level', value: 1 }] }
        it { is_expected.to be_a_kind_of(described_class) }
      end

      context 'is array of multiple Hashes' do
        let(:additional_payload) do
          [
            { name: 'logger.level', value: 1 },
            { name: 'profiling.enabled', value: true },
            { name: 'tracing.enabled', value: true },
          ]
        end
        it { is_expected.to be_a_kind_of(described_class) }
      end
    end

    context 'when :configuration' do
      context 'is nil' do
        let(:configuration) { nil }
        it { is_expected.to be_a_kind_of(described_class) }
      end

      context 'is array of one Hash' do
        let(:configuration) { [{ name: 'DD_AGENT_HOST', value: 'localhost' }] }
        it { is_expected.to be_a_kind_of(described_class) }
      end

      context 'is array of Configurations with multiple elements' do
        let(:configuration) do
          [
            { name: 'DD_AGENT_HOST', value: 'localhost' },
            { name: 'DD_AGENT_TRANSPORT', value: 'http' },
            { name: 'DD_TRACE_SAMPLE_RATE', value: '0.7' },
          ]
        end
        it { is_expected.to be_a_kind_of(described_class) }
      end
    end

    context 'when :dependencies' do
      context 'is nil' do
        let(:dependencies) { nil }
        it { is_expected.to be_a_kind_of(described_class) }
      end

      context 'is array of Dependency' do
        let(:dependencies) { [Datadog::Core::Telemetry::V1::Dependency.new(name: 'pg')] }
        it { is_expected.to be_a_kind_of(described_class) }
      end

      context 'is array of Dependencies with multiple elements' do
        let(:dependencies) do
          [
            Datadog::Core::Telemetry::V1::Dependency.new(name: 'pg'),
            Datadog::Core::Telemetry::V1::Dependency.new(name: 'kafka'),
            Datadog::Core::Telemetry::V1::Dependency.new(name: 'mongodb')
          ]
        end
        it { is_expected.to be_a_kind_of(described_class) }
      end
    end

    context 'when :install_signature' do
      context 'is nil' do
        let(:install_signature) { nil }
        it { is_expected.to be_a_kind_of(described_class) }
      end

      context 'is InstallSignature' do
        let(:integrations) do
          Datadog::Core::Telemetry::V1::InstallSignature.new(
            install_id: '123',
            install_type: 'docker',
            install_time: '1703188212'
          )
        end
        it { is_expected.to be_a_kind_of(described_class) }
      end
    end

    context 'when :integrations' do
      context 'is nil' do
        let(:integrations) { nil }
        it { is_expected.to be_a_kind_of(described_class) }
      end

      context 'is array of Integration' do
        let(:integrations) { [Datadog::Core::Telemetry::V1::Integration.new(name: 'pg', enabled: true)] }
        it { is_expected.to be_a_kind_of(described_class) }
      end

      context 'is array of Integrations with multiple elements' do
        let(:integrations) do
          [
            Datadog::Core::Telemetry::V1::Integration.new(name: 'pg', enabled: true),
            Datadog::Core::Telemetry::V1::Integration.new(name: 'kafka', enabled: true),
            Datadog::Core::Telemetry::V1::Integration.new(name: 'mongodb', enabled: false)
          ]
        end
        it { is_expected.to be_a_kind_of(described_class) }
      end
    end
  end

  describe '#to_h' do
    subject(:to_h) { app_started.to_h }

    context 'when attributes are all nil' do
      let(:additional_payload) { nil }
      let(:configuration) { nil }
      let(:dependencies) { nil }
      let(:install_signature) { nil }
      let(:integrations) { nil }

      it do
        is_expected.to eq({})
      end
    end

    context 'when only integrations provided' do
      let(:additional_payload) { nil }
      let(:configuration) { nil }
      let(:dependencies) { nil }
      let(:install_signature) { nil }
      let(:integrations) { [Datadog::Core::Telemetry::V1::Integration.new(name: 'pg', enabled: true)] }

      it do
        is_expected.to eq(
          integrations: [{ enabled: true, name: 'pg' }]
        )
      end
    end

    context 'when attributes are all defined' do
      let(:additional_payload) { { 'tracing.enabled' => true, 'profiling.enabled' => false } }
      let(:configuration) { { DD_AGENT_HOST: 'localhost', DD_TRACE_SAMPLE_RATE: '1' } }
      let(:dependencies) { [Datadog::Core::Telemetry::V1::Dependency.new(name: 'pg')] }
      let(:install_signature) do
        Datadog::Core::Telemetry::V1::InstallSignature.new(
          install_id: '123',
          install_type: 'docker',
          install_time: '1703188212'
        )
      end
      let(:integrations) { [Datadog::Core::Telemetry::V1::Integration.new(name: 'pg', enabled: true)] }

      it do
        is_expected.to eq(
          additional_payload: [{ name: 'tracing.enabled', value: true },
                               { name: 'profiling.enabled', value: false }],
          configuration: [{ name: 'DD_AGENT_HOST', value: 'localhost' },
                          { name: 'DD_TRACE_SAMPLE_RATE', value: '1' }],
          dependencies: [{ name: 'pg' }],
          install_signature: { install_id: '123', install_type: 'docker', install_time: '1703188212' },
          integrations: [{ enabled: true, name: 'pg' }]
        )
      end
    end
  end
end
