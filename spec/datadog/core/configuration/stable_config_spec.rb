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
      File.write(
        File.join(tmpdir, 'local_config.yaml'),
        local_config_content
      )
      File.write(
        File.join(tmpdir, 'fleet_config.yaml'),
        fleet_config_content
      )

      test_configurator = Datadog::Core::Configuration::StableConfig::Configurator.new
      Datadog::Core::Configuration::StableConfig::Testing.with_local_path(
        test_configurator,
        File.join(tmpdir, 'local_config.yaml')
      )
      Datadog::Core::Configuration::StableConfig::Testing.with_fleet_path(
        test_configurator,
        File.join(tmpdir, 'fleet_config.yaml')
      )

      allow(Datadog::Core::Configuration::StableConfig).to receive(:extract_configuration).and_return(
        test_configurator.get
      )
    end

    after do
      FileUtils.remove_entry_secure(tmpdir)
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
          expect(described_class.configuration).to eq(
            {
              local: {id: "12345", config: {"DD_LOGS_INJECTION" => "false"}},
              fleet: {id: "56789", config: {"DD_APPSEC_ENABLED" => "true"}}
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
          expect(described_class.configuration).to eq(
            {
              local: {config: {"DD_LOGS_INJECTION" => "false"}},
              fleet: {config: {"DD_APPSEC_ENABLED" => "true"}}
            }
          )
        end
      end
    end
  end
end
