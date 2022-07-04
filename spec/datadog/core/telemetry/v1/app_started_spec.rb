require 'spec_helper'

require 'datadog/core/telemetry/v1/app_started'
require 'datadog/core/telemetry/v1/configuration'
require 'datadog/core/telemetry/v1/dependency'
require 'datadog/core/telemetry/v1/integration'

RSpec.describe Datadog::Core::Telemetry::V1::AppStarted do
  subject(:app_started) do
    described_class.new(
      additional_payload: additional_payload,
      configuration: configuration,
      dependencies: dependencies,
      integrations: integrations,
    )
  end

  let(:additional_payload) { [Datadog::Core::Telemetry::V1::Configuration.new(name: 'ENV_VARIABLE')] }
  let(:configuration) { [Datadog::Core::Telemetry::V1::Configuration.new(name: 'DD_TRACE_DEBUG')] }
  let(:dependencies) { [Datadog::Core::Telemetry::V1::Dependency.new(name: 'pg')] }
  let(:integrations) { [Datadog::Core::Telemetry::V1::Integration.new(name: 'pg', enabled: true)] }

  it do
    is_expected.to have_attributes(
      additional_payload: additional_payload,
      configuration: configuration,
      dependencies: dependencies,
      integrations: integrations,
    )
  end

  describe '#initialize' do
    context 'when :additional_payload' do
      context 'is nil' do
        let(:additional_payload) { nil }
        it { is_expected.to be_a_kind_of(described_class) }
      end

      context 'is array of Configuration' do
        let(:additional_payload) { [Datadog::Core::Telemetry::V1::Configuration.new(name: 'ENV_VARIABLE')] }
        it { is_expected.to be_a_kind_of(described_class) }
      end

      context 'is array of Configurations with multiple elements' do
        let(:additional_payload) do
          [
            Datadog::Core::Telemetry::V1::Configuration.new(name: 'ENV_VARIABLE'),
            Datadog::Core::Telemetry::V1::Configuration.new(name: 'ANOTHER_VAR'),
            Datadog::Core::Telemetry::V1::Configuration.new(name: 'SOME_OTHER_VARIABLE')
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

      context 'is array of Configuration' do
        let(:configuration) { [Datadog::Core::Telemetry::V1::Configuration.new(name: 'DD_TRACE_DEBUG')] }
        it { is_expected.to be_a_kind_of(described_class) }
      end

      context 'is array of Configurations with multiple elements' do
        let(:configuration) do
          [
            Datadog::Core::Telemetry::V1::Configuration.new(name: 'DD_TRACE_DEBUG'),
            Datadog::Core::Telemetry::V1::Configuration.new(name: 'DD_SERVICE_NAME'),
            Datadog::Core::Telemetry::V1::Configuration.new(name: 'DD_ENV')
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
      let(:integrations) { nil }
      it { is_expected.to eq({}) }
    end

    context 'when attributes are all defined' do
      let(:additional_payload) { { 'tracing.enabled': true, 'profiling.enabled': false } }
      let(:configuration) { { DD_AGENT_HOST: 'localhost', DD_TRACE_SAMPLE_RATE: '1' } }
      let(:dependencies) { [Datadog::Core::Telemetry::V1::Dependency.new(name: 'pg')] }
      let(:integrations) { [Datadog::Core::Telemetry::V1::Integration.new(name: 'pg', enabled: true)] }

      before do
        allow(dependencies[0]).to receive(:to_h).and_return({ name: 'pg' })
        allow(integrations[0]).to receive(:to_h).and_return({ name: 'pg', enabled: true })
      end

      it do
        is_expected.to eq(
          additional_payload: [{ :name => 'tracing.enabled', :value => true },
                               { :name => 'profiling.enabled', :value => false }],
          configuration: [{ :name => 'DD_AGENT_HOST', :value => 'localhost' },
                          { :name => 'DD_TRACE_SAMPLE_RATE', :value => '1' }],
          dependencies: [{ name: 'pg' }],
          integrations: [{ name: 'pg', enabled: true }]
        )
      end
    end
  end
end
