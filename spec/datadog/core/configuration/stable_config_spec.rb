# frozen_string_literal: true

RSpec.describe Datadog::Core::Configuration::StableConfig do
  describe '#extract_configuration' do
    context 'when libdatadog API is not available' do
      it 'returns an empty hash' do
        stub_const('Datadog::Core::LIBDATADOG_API_FAILURE', 'test')
        expect(Datadog.logger).to receive(:debug).with('Cannot enable stable config: test')
        expect(described_class.extract_configuration).to eq({})
      end
    end
  end

  describe '#configuration', skip: !LibdatadogHelpers.supported? do
    context 'when libdatadog API is available' do
      before do
        FileUtils.mkdir_p('/tmp/datadog-agent/managed/datadog-agent/stable')
        # local config
        File.write(
          '/tmp/datadog-agent/application_monitoring.yaml',
          "config_id: 12345\napm_configuration_default:\n  DD_LOGS_INJECTION: false\n")
        # fleet config
        File.write(
          '/tmp/datadog-agent/managed/datadog-agent/stable/application_monitoring.yaml',
          "config_id: 56789\napm_configuration_default:\n  DD_APPSEC_ENABLED: true\n")

        allow(Datadog::Core::Configuration::StableConfig).to receive(:extract_configuration).and_return(
          Datadog::Core::Configuration::StableConfig::Configurator.new.
            with_local_path('/tmp/datadog-agent/application_monitoring.yaml').
            with_fleet_path('/tmp/datadog-agent/managed/datadog-agent/stable/application_monitoring.yaml').get
        )
      end

      after do
        FileUtils.rm_rf('/tmp/datadog-agent')
        Datadog::Core::Configuration::StableConfig.instance_variable_set(:@configuration, nil)
      end

      it 'returns the configuration' do
        expect(described_class.configuration).to eq(
          {
            local: {"DD_LOGS_INJECTION" => "false"},
            fleet: {"DD_APPSEC_ENABLED" => "true"},
          }
        )
      end
    end
  end
end
