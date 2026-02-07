# frozen_string_literal: true

require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/active_storage/configuration/settings'

RSpec.describe Datadog::Tracing::Contrib::ActiveStorage::Configuration::Settings do
  subject(:settings) { described_class.new }

  it { is_expected.to be_a_kind_of(Datadog::Tracing::Contrib::Configuration::Settings) }

  describe '#enabled' do
    subject(:enabled) { settings.enabled }

    it { is_expected.to be true }

    context 'when DD_TRACE_ACTIVE_STORAGE_ENABLED environment variable' do
      around do |example|
        ClimateControl.modify('DD_TRACE_ACTIVE_STORAGE_ENABLED' => environment_value) do
          example.run
        end
      end

      context 'is not defined' do
        let(:environment_value) { nil }

        it { is_expected.to be true }
      end

      context 'is set to true' do
        let(:environment_value) { 'true' }

        it { is_expected.to be true }
      end

      context 'is set to false' do
        let(:environment_value) { 'false' }

        it { is_expected.to be false }
      end
    end
  end

  describe '#analytics_enabled' do
    subject(:analytics_enabled) { settings.analytics_enabled }

    it { is_expected.to be false }

    context 'when DD_TRACE_ACTIVE_STORAGE_ANALYTICS_ENABLED environment variable' do
      around do |example|
        ClimateControl.modify('DD_TRACE_ACTIVE_STORAGE_ANALYTICS_ENABLED' => environment_value) do
          example.run
        end
      end

      context 'is not defined' do
        let(:environment_value) { nil }

        it { is_expected.to be false }
      end

      context 'is set to true' do
        let(:environment_value) { 'true' }

        it { is_expected.to be true }
      end

      context 'is set to false' do
        let(:environment_value) { 'false' }

        it { is_expected.to be false }
      end
    end
  end

  describe '#analytics_sample_rate' do
    subject(:analytics_sample_rate) { settings.analytics_sample_rate }

    it { is_expected.to eq(1.0) }

    context 'when DD_TRACE_ACTIVE_STORAGE_ANALYTICS_SAMPLE_RATE environment variable' do
      around do |example|
        ClimateControl.modify('DD_TRACE_ACTIVE_STORAGE_ANALYTICS_SAMPLE_RATE' => environment_value) do
          example.run
        end
      end

      context 'is not defined' do
        let(:environment_value) { nil }

        it { is_expected.to eq(1.0) }
      end

      context 'is set to 0.5' do
        let(:environment_value) { '0.5' }

        it { is_expected.to eq(0.5) }
      end

      context 'is set to 0.0' do
        let(:environment_value) { '0.0' }

        it { is_expected.to eq(0.0) }
      end
    end
  end

  describe '#service_name' do
    subject(:service_name) { settings.service_name }

    it { is_expected.to be_nil }

    context 'when configured' do
      before { settings.service_name = 'my-storage' }

      it { is_expected.to eq('my-storage') }
    end
  end
end
