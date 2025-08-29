require 'spec_helper'

require 'datadog/core/configuration/config_helper'

RSpec.describe Datadog::Core::Configuration::ConfigHelper do
  let(:supported_configurations) { {} }
  let(:aliases) { {} }
  let(:alias_to_canonical) { {} }
  let(:deprecations) { {} }
  subject { described_class.new }

  before do
    # Force reload of the constants with our mocked data
    stub_const('Datadog::Core::Configuration::SUPPORTED_CONFIGURATIONS', supported_configurations)
    stub_const('Datadog::Core::Configuration::ALIASES', aliases)
    stub_const('Datadog::Core::Configuration::DEPRECATIONS', deprecations)
    stub_const('Datadog::Core::Configuration::ALIAS_TO_CANONICAL', alias_to_canonical)
  end

  describe '#[]' do
    context 'with ENV' do
      let(:supported_configurations) { { 'DD_TRACE_ENABLED' => { version: ['A'] } } }

      around do |example|
        ClimateControl.modify('DD_TRACE_ENABLED' => 'true') do
          example.run
        end
      end

      it 'returns the environment variable value' do
        expect(subject['DD_TRACE_ENABLED']).to eq('true')
      end
    end

    context 'with a env var hash different from ENV' do
      subject { (described_class.new(env_vars: source_env_vars)) }
      let(:source_env_vars) { { 'DD_TRACE_ENABLED' => 'true' } }
      let(:supported_configurations) { { 'DD_TRACE_ENABLED' => { version: ['A'] } } }

      it 'returns the environment variable value' do
        expect(subject['DD_TRACE_ENABLED']).to eq('true')
      end
    end
  end

  describe '#fetch' do
    context 'with env var set' do
      let(:supported_configurations) { { 'DD_TRACE_ENABLED' => { version: ['A'] } } }

      around do |example|
        ClimateControl.modify('DD_TRACE_ENABLED' => 'true') do
          example.run
        end
      end

      it 'returns the environment variable value' do
        expect(subject.fetch('DD_TRACE_ENABLED')).to eq('true')
      end
    end

    context 'with env var not set' do
      let(:supported_configurations) { { 'DD_TRACE_ENABLED' => { version: ['A'] } } }

      it 'returns the default value when set' do
        expect(subject.fetch('DD_TRACE_ENABLED', 'default')).to eq('default')
      end

      it 'runs the given block if set' do
        expect(subject.fetch('DD_TRACE_ENABLED') { |k| "#{k} not found" }).to eq('DD_TRACE_ENABLED not found')
      end

      it 'raises a KeyError if no default value is set' do
        expect { subject.fetch('DD_TRACE_ENABLED') }.to raise_error(KeyError)
      end
    end
  end

  describe '#key?' do
    let(:supported_configurations) { { 'DD_TRACE_ENABLED' => { version: ['A'] } } }

    it 'returns false if the env var is not set' do
      expect(subject.key?('DD_TRACE_ENABLED')).to be(false)
    end

    context 'with env var set' do
      around do |example|
        ClimateControl.modify('DD_TRACE_ENABLED' => 'anything') do
          example.run
        end
      end

      it 'returns true if the env var is set' do
        expect(subject.key?('DD_TRACE_ENABLED')).to be(true)
      end
    end
  end

  describe '.get_environment_variable' do
    subject { described_class.get_environment_variable(name, env_vars: env_vars) }

    let(:name) { 'DD_TRACE_ENABLED' }
    let(:env_vars) { {} }

    before do
      # Reset instance variables that might be set by previous tests
      described_class.instance_variable_set(:@log_deprecations_called_with, nil)
    end

    context 'when the environment variable is supported' do
      let(:name) { 'DD_TRACE_ENABLED' }
      let(:env_vars) { { 'DD_TRACE_ENABLED' => 'true' } }
      let(:supported_configurations) { { 'DD_TRACE_ENABLED' => { version: ['A'] } } }

      it 'returns the environment variable value' do
        is_expected.to eq('true')
      end
    end

    context 'when the environment variable is not set' do
      let(:name) { 'DD_TRACE_ENABLED' }
      let(:env_vars) { {} }
      let(:supported_configurations) { { 'DD_TRACE_ENABLED' => { version: ['A'] } } }

      it 'returns nil' do
        is_expected.to be_nil
      end

      context 'when a default value is provided' do
        subject { described_class.get_environment_variable(name, 'default', env_vars: env_vars) }

        it 'returns the default value' do
          is_expected.to eq('default')
        end
      end
    end

    context 'when the environment variable has an alias' do
      let(:name) { 'DD_SERVICE' }
      let(:env_vars) { { 'OTEL_SERVICE_NAME' => 'my-service' } }
      let(:supported_configurations) { { 'DD_SERVICE' => { version: ['A'] } } }
      let(:aliases) { { 'DD_SERVICE' => ['OTEL_SERVICE_NAME'] } }

      it 'returns the alias value when the main env var is not set' do
        is_expected.to eq('my-service')
      end

      context 'when both main and alias are set' do
        let(:env_vars) { { 'DD_SERVICE' => 'main-service', 'OTEL_SERVICE_NAME' => 'alias-service' } }

        it 'returns the main environment variable value' do
          is_expected.to eq('main-service')
        end
      end
    end

    context 'when Datadog::CI is defined' do
      before do
        stub_const('Datadog::CI', Module.new)
      end

      let(:name) { 'DD_UNSUPPORTED_VAR' }
      let(:env_vars) { { 'DD_UNSUPPORTED_VAR' => 'value' } }
      let(:supported_configurations) { {} }

      # For now, datadog-ci-rb is not supported and we don't want to break it.
      it 'returns the environment variable value even if unsupported' do
        is_expected.to eq('value')
      end
    end

    context 'when environment variable starts with DD_ but is not supported' do
      let(:name) { 'DD_UNSUPPORTED_VAR' }
      let(:env_vars) { { 'DD_UNSUPPORTED_VAR' => 'value' } }
      let(:supported_configurations) { {} } # Override to make it unsupported

      context 'when not in test environment' do
        around do |example|
          described_class.instance_variable_set(:@raise_on_unknown_env_var, nil)

          example.run

          described_class.instance_variable_set(:@raise_on_unknown_env_var, true)
        end

        it 'returns nil' do
          is_expected.to be_nil
        end
      end

      context 'when in test environment' do
        it 'raises an error for unsupported DD_ variables' do
          expect { subject }.to raise_error(RuntimeError, /Missing DD_UNSUPPORTED_VAR env\/configuration/)
        end
      end
    end

    context 'when using a deprecated alias that does not start with DD_ or OTEL_' do
      let(:name) { 'DISABLE_DATADOG_RAILS' }
      let(:env_vars) { { 'DISABLE_DATADOG_RAILS' => 'true' } }
      let(:supported_configurations) { {'DD_DISABLE_DATADOG_RAILS' => { version: ['A'] } } }
      let(:aliases) { { 'DISABLE_DATADOG_RAILS' => ['DD_DISABLE_DATADOG_RAILS'] } }
      let(:alias_to_canonical) { { 'DISABLE_DATADOG_RAILS' => 'DD_DISABLE_DATADOG_RAILS' } }

      context 'when not in test environment' do
        around do |example|
          described_class.instance_variable_set(:@raise_on_unknown_env_var, nil)

          example.run

          described_class.instance_variable_set(:@raise_on_unknown_env_var, true)
        end

        it 'returns the environment variable value' do
          is_expected.to eq(nil)
        end
      end

      context 'when in test environment' do
        it 'raises an error suggesting the canonical name' do
          expect { subject }.to raise_error(RuntimeError, /Please use DD_DISABLE_DATADOG_RAILS instead/)
        end
      end
    end

    context 'when environment variable does not start with DD_ or OTEL_' do
      let(:name) { 'SOME_OTHER_VAR' }
      let(:env_vars) { { 'SOME_OTHER_VAR' => 'value' } }

      it 'returns the environment variable value' do
        is_expected.to eq('value')
      end
    end
  end

  describe '.log_deprecated_environment_variables' do
    let(:mock_io) { StringIO.new }
    let(:mock_logger) { Datadog::Core::Logger.new(mock_io) }

    before do
      # Reset instance variables that might be set by previous tests
      described_class.instance_variable_set(:@log_deprecations_called_with, nil)
    end

    context 'when the deprecated environment variable has an alias' do
      let(:env_vars) { { 'DD_PROFILING_PREVIEW_GVL_ENABLED' => 'true' } }
      let(:deprecations) { { 'DD_PROFILING_PREVIEW_GVL_ENABLED' => 'Use DD_PROFILING_GVL_ENABLED instead' } }
      let(:alias_to_canonical) { { 'DD_PROFILING_PREVIEW_GVL_ENABLED' => 'DD_PROFILING_GVL_ENABLED' } }

      it 'logs deprecation warnings for deprecated environment variables' do
        described_class.log_deprecated_environment_variables(mock_logger, env_vars: env_vars, source: 'test')
        expect(mock_io.string).to include('DD_PROFILING_PREVIEW_GVL_ENABLED test variable is deprecated, use DD_PROFILING_GVL_ENABLED instead.')
      end
    end

    context 'when the environment variable does not have an alias' do
      let(:env_vars) { { 'DD_PROFILING_PREVIEW_GVL_ENABLED' => 'true' } }
      let(:deprecations) { { 'DD_PROFILING_PREVIEW_GVL_ENABLED' => 'This will be removed in the next major version.' } }
      let(:alias_to_canonical) { {} }

      it 'logs deprecation warnings for deprecated environment variables with correct message' do
        described_class.log_deprecated_environment_variables(mock_logger, env_vars: env_vars, source: 'test')
        expect(mock_io.string).to include('DD_PROFILING_PREVIEW_GVL_ENABLED test variable is deprecated. This will be removed in the next major version.')
      end
    end

    context 'when called multiple times with the same source' do
      let(:env_vars) { { 'DD_PROFILING_PREVIEW_GVL_ENABLED' => 'true' } }
      let(:deprecations) { { 'DD_PROFILING_PREVIEW_GVL_ENABLED' => 'Use DD_PROFILING_GVL_ENABLED instead' } }
      let(:alias_to_canonical) { { 'DD_PROFILING_PREVIEW_GVL_ENABLED' => 'DD_PROFILING_GVL_ENABLED' } }

      it 'only logs deprecations once per source' do
        expect(Datadog::Core).to receive(:log_deprecation).once
        described_class.log_deprecated_environment_variables(mock_logger, env_vars: env_vars, source: 'test')
        described_class.log_deprecated_environment_variables(mock_logger, env_vars: env_vars, source: 'test')
      end
    end

    context 'when called with different sources' do
      let(:env_vars) { { 'DD_PROFILING_PREVIEW_GVL_ENABLED' => 'true' } }
      let(:deprecations) { { 'DD_PROFILING_PREVIEW_GVL_ENABLED' => 'Use DD_PROFILING_GVL_ENABLED instead' } }
      let(:alias_to_canonical) { { 'DD_PROFILING_PREVIEW_GVL_ENABLED' => 'DD_PROFILING_GVL_ENABLED' } }

      it 'logs deprecations for each source' do
        expect(Datadog::Core).to receive(:log_deprecation).twice
        described_class.log_deprecated_environment_variables(mock_logger, env_vars: env_vars, source: 'environment')
        described_class.log_deprecated_environment_variables(mock_logger, env_vars: env_vars, source: 'config_file')
      end
    end
  end

  describe '::log_deprecations_from_all_sources' do
    let(:mock_io) { StringIO.new }
    let(:mock_logger) { Datadog::Core::Logger.new(mock_io) }

    let(:env) { 'TEST' }
    let(:deprecated_env) { 'DEPRECATED_TEST' }
    let(:env_value) { 'test' }
    let(:deprecated_env_value) { 'old test' }
    let(:deprecations) { { deprecated_env => 'unused when there is an alias' } }
    let(:alias_to_canonical) { { deprecated_env => env } }

    before do
      Datadog::Core::Configuration::ConfigHelper.instance_variable_set(:@log_deprecations_called_with, nil)
    end

    context 'when deprecated env is set in ENV' do
      context 'env and deprecated_env found' do
        around do |example|
          ClimateControl.modify(env => env_value, deprecated_env => deprecated_env_value) do
            example.run
          end
        end

        it 'log deprecation warning' do
          expect(Datadog::Core).to receive(:log_deprecation)
          described_class.log_deprecations_from_all_sources(mock_logger)
        end
      end

      context 'env not found and deprecated_env found' do
        around do |example|
          ClimateControl.modify(deprecated_env => deprecated_env_value) do
            example.run
          end
        end

        it 'log deprecation warning' do
          expect(Datadog::Core).to receive(:log_deprecation)
          described_class.log_deprecations_from_all_sources(mock_logger)
        end
      end

      context 'env and deprecated_env not found' do
        it 'do not log deprecation warning' do
          expect(Datadog::Core).to_not receive(:log_deprecation)
          described_class.log_deprecations_from_all_sources(mock_logger)
        end
      end
    end

    context 'when deprecated env is set in local config' do
      before do
        allow(Datadog::Core::Configuration::StableConfig).to receive(:configuration).and_return({
          local: {
            config: {
              deprecated_env => deprecated_env_value
            }
          }
        })
      end

      it 'log deprecation warning' do
        expect(Datadog::Core).to receive(:log_deprecation)
        described_class.log_deprecations_from_all_sources(mock_logger)
      end
    end

    context 'when deprecated env is set in fleet config' do
      before do
        allow(Datadog::Core::Configuration::StableConfig).to receive(:configuration).and_return({
          fleet: {
            config: {
              deprecated_env => deprecated_env_value
            }
          }
        })
      end

      it 'log deprecation warning' do
        expect(Datadog::Core).to receive(:log_deprecation)
        described_class.log_deprecations_from_all_sources(mock_logger)
      end
    end

    context 'when deprecated env is set in ENV, local and fleet config' do
      before do
        allow(Datadog::Core::Configuration::StableConfig).to receive(:configuration).and_return({
          local: {
            config: {
              deprecated_env => deprecated_env_value
            }
          },
          fleet: {
            config: {
              deprecated_env => deprecated_env_value
            }
          }
        })
      end

      around do |example|
        ClimateControl.modify(env => env_value, deprecated_env => deprecated_env_value) do
          example.run
        end
      end

      it 'log deprecation warning three times' do
        expect(Datadog::Core).to receive(:log_deprecation).exactly(3).times
        described_class.log_deprecations_from_all_sources(mock_logger)
      end
    end
  end

  describe 'test environment has @raise_on_unknown_env_var set to true' do
    it { expect(Datadog::Core::Configuration::ConfigHelper.instance_variable_get(:@raise_on_unknown_env_var)).to be(true) }
  end
end
