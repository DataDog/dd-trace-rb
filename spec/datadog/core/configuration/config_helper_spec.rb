require 'spec_helper'

require 'datadog/core/configuration/config_helper'

RSpec.describe Datadog::Core::Configuration::ConfigHelper do
  let(:supported_configurations) { {} }
  let(:aliases) { {} }
  let(:alias_to_canonical) { {} }
  let(:deprecations) { {} }
  let(:test_class) { Class.new { include Datadog::Core::Configuration::ConfigHelper } }
  let(:instance) { test_class.new }

  around do |example|
    # Force reload of the constants with our mocked data
    original_supported_configurations = Datadog::Core::Configuration::SUPPORTED_CONFIGURATIONS
    original_aliases = Datadog::Core::Configuration::ALIASES
    original_deprecations = Datadog::Core::Configuration::DEPRECATIONS
    original_alias_to_canonical = Datadog::Core::Configuration::ALIAS_TO_CANONICAL

    Datadog::Core::Configuration.send(:remove_const, :SUPPORTED_CONFIGURATIONS)
    Datadog::Core::Configuration.const_set(:SUPPORTED_CONFIGURATIONS, supported_configurations)

    Datadog::Core::Configuration.send(:remove_const, :ALIASES)
    Datadog::Core::Configuration.const_set(:ALIASES, aliases)

    Datadog::Core::Configuration.send(:remove_const, :DEPRECATIONS)
    Datadog::Core::Configuration.const_set(:DEPRECATIONS, deprecations)

    Datadog::Core::Configuration.send(:remove_const, :ALIAS_TO_CANONICAL)
    Datadog::Core::Configuration.const_set(:ALIAS_TO_CANONICAL, alias_to_canonical)

    example.run

    # Revert the constants to their original values
    Datadog::Core::Configuration.send(:remove_const, :SUPPORTED_CONFIGURATIONS)
    Datadog::Core::Configuration.const_set(:SUPPORTED_CONFIGURATIONS, original_supported_configurations)

    Datadog::Core::Configuration.send(:remove_const, :ALIASES)
    Datadog::Core::Configuration.const_set(:ALIASES, original_aliases)

    Datadog::Core::Configuration.send(:remove_const, :DEPRECATIONS)
    Datadog::Core::Configuration.const_set(:DEPRECATIONS, original_deprecations)

    Datadog::Core::Configuration.send(:remove_const, :ALIAS_TO_CANONICAL)
    Datadog::Core::Configuration.const_set(:ALIAS_TO_CANONICAL, original_alias_to_canonical)
  end

  describe '#get_environment_variable' do
    subject(:get_env_var) { instance.get_environment_variable(name, env_vars: env_vars, source: source) }

    let(:name) { 'DD_TRACE_ENABLED' }
    let(:env_vars) { {} }
    let(:source) { 'test' }

    before do
      # Reset instance variables that might be set by previous tests
      instance.instance_variable_set(:@log_deprecations_called_with, nil)
      instance.instance_variable_set(:@config_helper_logger, nil)
      instance.instance_variable_set(:@dd_test_environment, nil)
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
        it 'returns nil' do
          is_expected.to be_nil
        end
      end

      context 'when in test environment' do
        before do
          instance.send(:dd_test_environment!)
        end

        it 'raises an error for unsupported DD_ variables' do
          expect { get_env_var }.to raise_error(RuntimeError, /Missing DD_UNSUPPORTED_VAR env\/configuration/)
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
        it 'returns the environment variable value' do
          is_expected.to eq(nil)
        end
      end

      context 'when in test environment' do
        before do
          instance.send(:dd_test_environment!)
        end

        it 'raises an error suggesting the canonical name' do
          expect { get_env_var }.to raise_error(RuntimeError, /Please use DD_DISABLE_DATADOG_RAILS instead/)
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

    context 'with deprecation logging' do
      let(:name) { 'DD_PROFILING_PREVIEW_GVL_ENABLED' }
      let(:env_vars) { { 'DD_PROFILING_PREVIEW_GVL_ENABLED' => 'true' } }
      let(:supported_configurations) { { 'DD_PROFILING_PREVIEW_GVL_ENABLED' => { version: ['A'] } } }
      let(:aliases) { { 'DD_PROFILING_PREVIEW_GVL_ENABLED' => ['DD_PROFILING_GVL_ENABLED'] } }
      let(:deprecations) { { 'DD_PROFILING_PREVIEW_GVL_ENABLED' => 'Use DD_PROFILING_GVL_ENABLED instead' } }
      let(:alias_to_canonical) { { 'DD_PROFILING_PREVIEW_GVL_ENABLED' => 'DD_PROFILING_GVL_ENABLED' } }
      let(:mock_io) { StringIO.new }
      let(:mock_logger) { Datadog::Core::Logger.new(mock_io) }

      before do
        allow(Datadog::Core::Logger).to receive(:new).and_return(mock_logger)
      end

      it 'logs deprecation warnings for deprecated environment variables' do
        get_env_var
        expect(mock_io.string).to include('DD_PROFILING_PREVIEW_GVL_ENABLED test variable is deprecated, use DD_PROFILING_GVL_ENABLED instead.')
      end

      context 'when the environment variable does not have an alias' do
        let(:deprecations) { { 'DD_PROFILING_PREVIEW_GVL_ENABLED' => 'This will be removed in the next major version.' } }
        let(:alias_to_canonical) { {} }
        it 'logs deprecation warnings for deprecated environment variables with correct message' do
          get_env_var
          expect(mock_io.string).to include('DD_PROFILING_PREVIEW_GVL_ENABLED test variable is deprecated. This will be removed in the next major version.')
        end
      end

      context 'when called multiple times with the same source' do
        it 'only logs deprecations once per source' do
          expect(Datadog::Core).to receive(:log_deprecation).once
          instance.get_environment_variable(name, env_vars: env_vars, source: source)
          instance.get_environment_variable(name, env_vars: env_vars, source: source)
        end
      end

      context 'when called with different sources' do
        it 'logs deprecations for each source' do
          expect(Datadog::Core).to receive(:log_deprecation).twice
          instance.get_environment_variable(name, env_vars: env_vars, source: 'environment')
          instance.get_environment_variable(name, env_vars: env_vars, source: 'config_file')
        end
      end
    end
  end
end
