require 'spec_helper'

require 'datadog/core/configuration/config_helper'

RSpec.describe Datadog::Core::Configuration::ConfigHelper do
  describe '#initialize' do
    subject { described_class.new }

    it 'initializes with correct defaults' do
      expect(subject.instance_variable_get(:@source_env)).to eq(ENV)
      expect(subject.instance_variable_get(:@supported_configurations)).to eq(Datadog::Core::Configuration::SUPPORTED_CONFIGURATIONS)
      expect(subject.instance_variable_get(:@aliases)).to eq(Datadog::Core::Configuration::ALIASES)
      expect(subject.instance_variable_get(:@alias_to_canonical)).to eq(Datadog::Core::Configuration::ALIAS_TO_CANONICAL)
      expect(subject.instance_variable_get(:@raise_on_unknown_env_var)).to eq(false)
    end
  end

  describe '#[]' do
    subject do
      described_class.new(
        source_env: { 'DD_SUPPORTED_ENV_VAR' => 'true' },
        supported_configurations: { 'DD_SUPPORTED_ENV_VAR' => { version: ['A'] } }
      )
    end

    it 'returns the environment variable value' do
      expect(subject['DD_SUPPORTED_ENV_VAR']).to eq('true')
    end
  end

  describe '#fetch' do
    subject do
      described_class.new(source_env: source_env, supported_configurations: { 'DD_SUPPORTED_ENV_VAR' => { version: ['A'] } })
    end

    context 'with env var set' do
      let(:source_env) { { 'DD_SUPPORTED_ENV_VAR' => 'true' } }

      it 'returns the environment variable value' do
        expect(subject.fetch('DD_SUPPORTED_ENV_VAR')).to eq('true')
      end
    end

    context 'with env var not set' do
      let(:source_env) { {} }

      it 'returns the default value when set' do
        expect(subject.fetch('DD_SUPPORTED_ENV_VAR', 'default')).to eq('default')
      end

      it 'runs the given block if set' do
        expect(subject.fetch('DD_SUPPORTED_ENV_VAR') { |k| "#{k} not found" }).to eq('DD_SUPPORTED_ENV_VAR not found')
      end

      it 'raises a KeyError if no default value is set' do
        expect { subject.fetch('DD_SUPPORTED_ENV_VAR') }.to raise_error(KeyError)
      end
    end
  end

  describe '#key?' do
    subject do
      described_class.new(source_env: source_env, supported_configurations: { 'DD_SUPPORTED_ENV_VAR' => { version: ['A'] } })
    end

    context 'with env var not set' do
      let(:source_env) { {} }

      it 'returns false if the env var is not set' do
        expect(subject.key?('DD_SUPPORTED_ENV_VAR')).to be(false)
      end
    end

    context 'with env var set' do
      let(:source_env) { { 'DD_SUPPORTED_ENV_VAR' => 'anything' } }

      it 'returns true if the env var is set' do
        expect(subject.key?('DD_SUPPORTED_ENV_VAR')).to be(true)
      end
    end
  end

  describe '#get_environment_variable' do
    subject do
      described_class.new(
        source_env: source_env,
        supported_configurations: supported_configurations,
        aliases: aliases,
        alias_to_canonical: alias_to_canonical,
        raise_on_unknown_env_var: raise_on_unknown_env_var
      )
    end

    context 'when the environment variable is supported' do
      subject do
        described_class.new(
          source_env: { 'DD_SUPPORTED_ENV_VAR' => 'true' },
          supported_configurations: { 'DD_SUPPORTED_ENV_VAR' => { version: ['A'] } }
        )
      end

      it 'returns the environment variable value' do
        expect(subject.get_environment_variable('DD_SUPPORTED_ENV_VAR')).to eq('true')
      end
    end

    context 'when the environment variable is not set' do
      subject do
        described_class.new(
          source_env: {},
          supported_configurations: { 'DD_SUPPORTED_ENV_VAR' => { version: ['A'] } }
        )
      end

      it 'returns nil' do
        expect(subject.get_environment_variable('DD_SUPPORTED_ENV_VAR')).to be_nil
      end

      context 'when a default value is provided' do
        it 'returns the default value' do
          expect(subject.get_environment_variable('DD_SUPPORTED_ENV_VAR', 'default')).to eq('default')
        end
      end
    end

    context 'when the environment variable has an alias' do
      subject do
        described_class.new(
          source_env: { 'OTEL_SUPPORTED_ENV_VAR' => 'my-service' },
          supported_configurations: { 'DD_SUPPORTED_ENV_VAR' => { version: ['A'] } },
          aliases: { 'DD_SUPPORTED_ENV_VAR' => ['OTEL_SUPPORTED_ENV_VAR'] }
        )
      end

      it 'returns the alias value when the main env var is not set' do
        expect(subject.get_environment_variable('DD_SUPPORTED_ENV_VAR')).to eq('my-service')
      end

      context 'when both main and alias are set' do
        subject do
          described_class.new(
            source_env: { 'DD_SUPPORTED_ENV_VAR' => 'main-service', 'OTEL_SUPPORTED_ENV_VAR' => 'alias-service' },
            supported_configurations: { 'DD_SUPPORTED_ENV_VAR' => { version: ['A'] } },
            aliases: { 'DD_SUPPORTED_ENV_VAR' => ['OTEL_SUPPORTED_ENV_VAR'] }
          )
        end

        it 'returns the main environment variable value' do
          expect(subject.get_environment_variable('DD_SUPPORTED_ENV_VAR')).to eq('main-service')
        end
      end
    end

    context 'when Datadog::CI is defined' do
      before do
        stub_const('Datadog::CI', Module.new)
      end

      subject do
        described_class.new(
          source_env: { 'DD_UNSUPPORTED_VAR' => 'value' },
          supported_configurations: {}
        )
      end

      # For now, datadog-ci-rb is not supported and we don't want to break it.
      it 'returns the environment variable value even if unsupported' do
        expect(subject.get_environment_variable('DD_UNSUPPORTED_VAR')).to eq('value')
      end
    end

    context 'when environment variable starts with DD_ but is not supported' do
      subject do
        described_class.new(
          source_env: { 'DD_UNSUPPORTED_VAR' => 'value' },
          supported_configurations: {},
          raise_on_unknown_env_var: raise_on_unknown_env_var
        )
      end

      context 'when not in test environment' do
        let(:raise_on_unknown_env_var) { false }

        it 'returns nil' do
          expect(subject.get_environment_variable('DD_UNSUPPORTED_VAR')).to be_nil
        end
      end

      context 'when in test environment' do
        let(:raise_on_unknown_env_var) { true }

        it 'raises an error for unsupported DD_ variables' do
          expect { subject.get_environment_variable('DD_UNSUPPORTED_VAR') }.to raise_error(RuntimeError, /Missing DD_UNSUPPORTED_VAR env\/configuration/)
        end
      end
    end

    context 'when using a deprecated alias that does not start with DD_ or OTEL_' do
      subject do
        described_class.new(
          source_env: { 'SUPPORTED_ENV_VAR' => 'true' },
          supported_configurations: { 'DD_SUPPORTED_ENV_VAR' => { version: ['A'] } },
          aliases: { 'DD_SUPPORTED_ENV_VAR' => ['SUPPORTED_ENV_VAR'] },
          alias_to_canonical: { 'SUPPORTED_ENV_VAR' => 'DD_SUPPORTED_ENV_VAR' },
          raise_on_unknown_env_var: raise_on_unknown_env_var
        )
      end

      context 'when not in test environment' do
        let(:raise_on_unknown_env_var) { false }

        it 'returns the environment variable value' do
          expect(subject.get_environment_variable('SUPPORTED_ENV_VAR')).to eq(nil)
        end
      end

      context 'when in test environment' do
        let(:raise_on_unknown_env_var) { true }

        it 'raises an error suggesting the canonical name' do
          expect { subject.get_environment_variable('SUPPORTED_ENV_VAR') }.to raise_error(RuntimeError, /Please use DD_SUPPORTED_ENV_VAR instead/)
        end
      end
    end

    context 'when environment variable does not start with DD_ or OTEL_' do
      subject do
        described_class.new(
          source_env: { 'SOME_OTHER_VAR' => 'value' },
          supported_configurations: {},
        )
      end

      it 'returns the environment variable value' do
        expect(subject.get_environment_variable('SOME_OTHER_VAR')).to eq('value')
      end
    end
  end

  describe 'test environment has @raise_on_unknown_env_var set to true' do
    it { expect(Datadog::DATADOG_ENV.instance_variable_get(:@raise_on_unknown_env_var)).to be(true) }
  end
end
