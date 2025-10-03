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

  describe '#configuration', skip: !LibdatadogHelpers.supported? do
    let(:tmpdir) { Dir.mktmpdir }
    before do
      Datadog::Core::Configuration::StableConfig.instance_variable_set(:@configuration, nil)

      File.write(
        File.join(tmpdir, 'local_config.yaml'),
        local_config_content
      ) if defined?(local_config_content)
      File.write(
        File.join(tmpdir, 'fleet_config.yaml'),
        fleet_config_content
      ) if defined?(fleet_config_content)

      test_configurator = Datadog::Core::Configuration::StableConfig::Configurator.new
      Datadog::Core::Configuration::StableConfig::Testing.with_local_path(
        test_configurator,
        File.join(tmpdir, 'local_config.yaml')
      ) if defined?(local_config_content)
      Datadog::Core::Configuration::StableConfig::Testing.with_fleet_path(
        test_configurator,
        File.join(tmpdir, 'fleet_config.yaml')
      ) if defined?(fleet_config_content)

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
      end

      context 'with DD_TRACE_DEBUG set during configuration initialization' do
        before do
          described_class.const_get(:LOG_ONLY_ONCE).send(:reset_ran_once_state_for_tests)
        end

        # Reset DD_TRACE_DEBUG to nil as its precedence is higher than local config file
        around do |example|
          ClimateControl.modify('DD_TRACE_DEBUG' => nil) do
            example.run
          end
        end

        context 'to true in fleet config' do
          let(:fleet_config_content) do
            <<~YAML
            apm_configuration_default:
              DD_TRACE_DEBUG: true
            YAML
          end

          it 'prints debug logs' do
            # Datadog.logger is not reset between tests, so we need to build a new logger
            expect { described_class.log_result(Datadog::Core::Configuration::Components.build_logger(Datadog.configuration)) }.to output(/Reading stable configuration from files/).to_stdout
          end
        end

        context 'to true in local config' do
          let(:local_config_content) do
            <<~YAML
            apm_configuration_default:
              DD_TRACE_DEBUG: true
            YAML
          end

          it 'prints debug logs' do
            # Datadog.logger is not reset between tests, so we need to build a new logger
            expect { described_class.log_result(Datadog::Core::Configuration::Components.build_logger(Datadog.configuration)) }.to output(/Reading stable configuration from files/).to_stdout
          end
        end

        context 'to true in local config and false in fleet config' do
          let(:local_config_content) do
            <<~YAML
            apm_configuration_default:
              DD_TRACE_DEBUG: true
            YAML
          end

          let(:fleet_config_content) do
            <<~YAML
            apm_configuration_default:
              DD_TRACE_DEBUG: false
            YAML
          end

          it 'respects priority and does not print debug logs' do
            # Datadog.logger is not reset between tests, so we need to build a new logger
            expect { described_class.log_result(Datadog::Core::Configuration::Components.build_logger(Datadog.configuration)) }.not_to output(/Reading stable configuration from files/).to_stdout
          end
        end
      end
    end
  end
end
