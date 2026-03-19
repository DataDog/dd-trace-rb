# frozen_string_literal: true

require 'datadog/core'
require 'datadog/tracing/stats/ext'

RSpec.describe 'Datadog::Tracing::Stats configuration' do
  subject(:settings) { Datadog::Core::Configuration::Settings.new }

  describe 'tracing.stats_computation' do
    describe '#enabled' do
      context 'when DD_TRACE_STATS_COMPUTATION_ENABLED is not set' do
        it 'defaults to false' do
          expect(settings.tracing.stats_computation.enabled).to be false
        end
      end

      context 'when set programmatically' do
        it 'can be set to true' do
          settings.tracing.stats_computation.enabled = true
          expect(settings.tracing.stats_computation.enabled).to be true
        end

        it 'can be set to false' do
          settings.tracing.stats_computation.enabled = false
          expect(settings.tracing.stats_computation.enabled).to be false
        end
      end

      context 'when DD_TRACE_STATS_COMPUTATION_ENABLED is set' do
        around do |example|
          ClimateControl.modify('DD_TRACE_STATS_COMPUTATION_ENABLED' => env_value) do
            example.run
          end
        end

        context 'to true' do
          let(:env_value) { 'true' }

          it 'returns true' do
            expect(settings.tracing.stats_computation.enabled).to be true
          end
        end

        context 'to false' do
          let(:env_value) { 'false' }

          it 'returns false' do
            expect(settings.tracing.stats_computation.enabled).to be false
          end
        end
      end
    end
  end
end
