# frozen_string_literal: true

RSpec.describe Datadog::Core::Configuration::StableConfig do
  before do
    Datadog::Core::Configuration::StableConfig.instance_variable_set(:@configuration, nil)
  end

  describe '#extract_configuration' do
    context 'when libdatadog API is not available' do
      it 'returns an empty hash' do
        stub_const('Datadog::Core::LIBDATADOG_API_FAILURE', 'test')
        expect(Datadog.config_init_logger).to receive(:debug).with('Cannot enable stable config: test')
        expect(described_class.extract_configuration).to eq({})
      end
    end
  end

  describe '#configuration' do
    let(:tmpdir) { Dir.mktmpdir }
    before do
      skip_if_libdatadog_not_supported(self)

      Datadog::Core::Configuration::StableConfig.instance_variable_set(:@configuration, nil)

      if defined?(local_config_content)
        File.write(
          File.join(tmpdir, 'local_config.yaml'),
          local_config_content
        )
      end
      if defined?(fleet_config_content)
        File.write(
          File.join(tmpdir, 'fleet_config.yaml'),
          fleet_config_content
        )
      end

      test_configurator = Datadog::Core::Configuration::StableConfig::Configurator.new
      if defined?(local_config_content)
        Datadog::Core::Configuration::StableConfig::Testing.with_local_path(
          test_configurator,
          File.join(tmpdir, 'local_config.yaml')
        )
      end
      if defined?(fleet_config_content)
        Datadog::Core::Configuration::StableConfig::Testing.with_fleet_path(
          test_configurator,
          File.join(tmpdir, 'fleet_config.yaml')
        )
      end

      allow_any_instance_of(Datadog::Core::Configuration::StableConfig::Configurator).to receive(:get).and_return(
        test_configurator.get
      )
    end

    after do
      FileUtils.remove_entry_secure(tmpdir)

      Datadog::Core::Configuration::StableConfig.instance_variable_set(:@configuration, nil)
    end

    context 'when libdatadog API is available' do
      context 'with config_id' do
        let(:local_config_content) do
          <<~YAML
            config_id: 12345
            apm_configuration_default:
              DD_LOGS_INJECTION: false
          YAML
        end

        let(:fleet_config_content) do
          <<~YAML
            config_id: 56789
            apm_configuration_default:
              DD_APPSEC_ENABLED: true
          YAML
        end

        it 'returns the configuration' do
          expect(described_class.configuration).to include(
            {
              local: {id: "12345", config: {"DD_LOGS_INJECTION" => "false"}},
              fleet: {id: "56789", config: {"DD_APPSEC_ENABLED" => "true"}},
              logs: be_a(String)
            }
          )
        end

        it 'sets Datadog.configuration accordingly' do
          expect(Datadog.configuration.tracing.log_injection).to be false
          expect(Datadog.configuration.tracing.send(:resolve_option, :log_injection).precedence_set).to eq(Datadog::Core::Configuration::Option::Precedence::LOCAL_STABLE)
          expect(Datadog.configuration.appsec.enabled).to be true
          expect(Datadog.configuration.appsec.send(:resolve_option, :enabled).precedence_set).to eq(Datadog::Core::Configuration::Option::Precedence::FLEET_STABLE)
        end
      end

      context 'without config_id' do
        let(:local_config_content) do
          <<~YAML
            apm_configuration_default:
              DD_LOGS_INJECTION: false
          YAML
        end

        let(:fleet_config_content) do
          <<~YAML
            apm_configuration_default:
              DD_APPSEC_ENABLED: true
          YAML
        end

        it 'returns the configuration' do
          expect(described_class.configuration).to include(
            {
              local: {config: {"DD_LOGS_INJECTION" => "false"}},
              fleet: {config: {"DD_APPSEC_ENABLED" => "true"}},
              logs: be_a(String)
            }
          )
        end

        it 'sets Datadog.configuration accordingly' do
          expect(Datadog.configuration.tracing.log_injection).to be false
          expect(Datadog.configuration.tracing.send(:resolve_option, :log_injection).precedence_set).to eq(Datadog::Core::Configuration::Option::Precedence::LOCAL_STABLE)
          expect(Datadog.configuration.appsec.enabled).to be true
          expect(Datadog.configuration.appsec.send(:resolve_option, :enabled).precedence_set).to eq(Datadog::Core::Configuration::Option::Precedence::FLEET_STABLE)
        end
      end

      context 'with local and fleet config setting the same option' do
        let(:local_config_content) do
          <<~YAML
            apm_configuration_default:
              DD_TRACE_RATE_LIMIT: 10
          YAML
        end

        let(:fleet_config_content) do
          <<~YAML
            apm_configuration_default:
              DD_TRACE_RATE_LIMIT: 20
          YAML
        end

        it 'sets Datadog.configuration accordingly' do
          expect(Datadog.configuration.tracing.sampling.rate_limit).to eq(20)
          expect(Datadog.configuration.tracing.sampling.send(:resolve_option, :rate_limit).precedence_set).to eq(Datadog::Core::Configuration::Option::Precedence::FLEET_STABLE)
          # Currently, libdatadog only returns the fleet config value if both are set. This will change in the future, and it will returns both values.
          # Datadog.configuration.tracing.sampling.unset_option(:rate_limit, precedence: Datadog::Core::Configuration::Option::Precedence::FLEET_STABLE)
          # # Should fallback to local config
          # expect(Datadog.configuration.tracing.sampling.rate_limit).to eq(10)
          # expect(Datadog.configuration.tracing.sampling.send(:resolve_option, :rate_limit).precedence_set).to eq(Datadog::Core::Configuration::Option::Precedence::LOCAL_STABLE)
        end
      end
    end
  end

  describe '#log_result' do
    before do
      described_class.const_get(:LOG_ONLY_ONCE).send(:reset_ran_once_state_for_tests)
    end

    it 'calls logger.debug' do
      logger = double('test logger')
      expect(logger).to receive(:debug).with(/Reading stable configuration from files/)

      described_class.log_result(logger)
    end
  end
end
