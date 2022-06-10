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

      context 'is empty' do
        let(:additional_payload) { [] }
        it { expect { app_started }.to raise_error(ArgumentError) }
      end

      context 'is array of Hashes' do
        let(:additional_payload) { [{ :name => 'ENV_VARIABLE' }] }
        it { expect { app_started }.to raise_error(ArgumentError) }
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

      context 'is empty' do
        let(:configuration) { [] }
        it { expect { app_started }.to raise_error(ArgumentError) }
      end

      context 'is array of Hashes' do
        let(:configuration) { [{ :name => 'DD_TRACE_DEBUG' }] }
        it { expect { app_started }.to raise_error(ArgumentError) }
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

      context 'is empty' do
        let(:dependencies) { [] }
        it { expect { app_started }.to raise_error(ArgumentError) }
      end

      context 'is array of Hashes' do
        let(:dependencies) { [{ :name => 'pg' }] }
        it { expect { app_started }.to raise_error(ArgumentError) }
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

      context 'is empty' do
        let(:integrations) { [] }
        it { expect { app_started }.to raise_error(ArgumentError) }
      end

      context 'is array of Hashes' do
        let(:integrations) { [{ :name => 'pg', :enabled => true }] }
        it { expect { app_started }.to raise_error(ArgumentError) }
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

    context 'when all parameters' do
      context 'are nil' do
        let(:additional_payload) { nil }
        let(:configuration) { nil }
        let(:dependencies) { nil }
        let(:integrations) { nil }
        it { expect { app_started }.to raise_error(ArgumentError) }
      end
    end
  end
end
