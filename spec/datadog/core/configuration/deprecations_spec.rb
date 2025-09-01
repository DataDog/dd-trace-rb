require 'spec_helper'

require 'datadog/core/configuration/deprecations'

RSpec.describe Datadog::Core::Configuration::Deprecations do
  describe '.log_deprecations_from_all_sources' do
    let(:mock_io) { StringIO.new }
    let(:mock_logger) { Datadog::Core::Logger.new(mock_io) }

    subject do
      described_class.log_deprecations_from_all_sources(
        mock_logger,
        deprecations: { 'DEPRECATED_TEST' => 'unused when there is an alias' },
        alias_to_canonical: { 'DEPRECATED_TEST' => 'TEST' }
      )
    end

    before do
      described_class.const_get('LOG_DEPRECATIONS_ONLY_ONCE').send(:reset_ran_once_state_for_tests)
    end

    context 'when deprecated env is set in ENV' do
      context 'env and deprecated_env found' do
        around do |example|
          ClimateControl.modify('TEST' => 'test', 'DEPRECATED_TEST' => 'old test') do
            example.run
          end
        end

        it 'log deprecation warning' do
          expect(Datadog::Core).to receive(:log_deprecation)
          subject
        end
      end

      context 'env not found and deprecated_env found' do
        around do |example|
          ClimateControl.modify('DEPRECATED_TEST' => 'old test') do
            example.run
          end
        end

        it 'log deprecation warning' do
          expect(Datadog::Core).to receive(:log_deprecation)
          subject
        end
      end

      context 'env and deprecated_env not found' do
        it 'do not log deprecation warning' do
          expect(Datadog::Core).to_not receive(:log_deprecation)
          subject
        end
      end
    end

    context 'when deprecated env is set in local config' do
      before do
        allow(Datadog::Core::Configuration::StableConfig).to receive(:configuration).and_return({
          local: {
            config: {
              'DEPRECATED_TEST' => 'old test'
            }
          }
        })
      end

      it 'log deprecation warning' do
        expect(Datadog::Core).to receive(:log_deprecation)
        subject
      end
    end

    context 'when deprecated env is set in fleet config' do
      before do
        allow(Datadog::Core::Configuration::StableConfig).to receive(:configuration).and_return({
          fleet: {
            config: {
              'DEPRECATED_TEST' => 'old test'
            }
          }
        })
      end

      it 'log deprecation warning' do
        expect(Datadog::Core).to receive(:log_deprecation)
        subject
      end
    end

    context 'when deprecated env is set in ENV, local and fleet config' do
      before do
        allow(Datadog::Core::Configuration::StableConfig).to receive(:configuration).and_return({
          local: {
            config: {
              'DEPRECATED_TEST' => 'old test'
            }
          },
          fleet: {
            config: {
              'DEPRECATED_TEST' => 'old test'
            }
          }
        })
      end

      around do |example|
        ClimateControl.modify('TEST' => 'test', 'DEPRECATED_TEST' => 'old test') do
          example.run
        end
      end

      it 'log deprecation warning three times' do
        expect(Datadog::Core).to receive(:log_deprecation).exactly(3).times
        subject
      end
    end
  end

  describe '.log_deprecated_environment_variables' do
    let(:mock_io) { StringIO.new }
    let(:mock_logger) { Datadog::Core::Logger.new(mock_io) }
    let(:env_vars) { {} }
    let(:source) { 'test' }
    let(:deprecations) { {} }
    let(:alias_to_canonical) { {} }

    subject do
      described_class.send(:log_deprecated_environment_variables,
        mock_logger,
        env_vars,
        source,
        deprecations,
        alias_to_canonical
      )
    end

    context 'when the deprecated environment variable has an alias' do
      let(:env_vars) { { 'DD_DEPRECATED_ENV_VAR' => 'true' } }
      let(:deprecations) { { 'DD_DEPRECATED_ENV_VAR' => 'This should not appear in the output' } }
      let(:alias_to_canonical) { { 'DD_DEPRECATED_ENV_VAR' => 'DD_SUPPORTED_ENV_VAR' } }

      it 'logs deprecation warnings for deprecated environment variables' do
        subject
        expect(mock_io.string).to include('DD_DEPRECATED_ENV_VAR test variable is deprecated, use DD_SUPPORTED_ENV_VAR instead.')
      end
    end

    context 'when the environment variable does not have an alias' do
      let(:env_vars) { { 'DD_DEPRECATED_ENV_VAR' => 'true' } }
      let(:deprecations) { { 'DD_DEPRECATED_ENV_VAR' => 'This will be removed in the next major version.' } }
      let(:alias_to_canonical) { {} }

      it 'logs deprecation warnings for deprecated environment variables with correct message' do
        subject
        expect(mock_io.string).to include('DD_DEPRECATED_ENV_VAR test variable is deprecated. This will be removed in the next major version.')
      end
    end
  end
end
