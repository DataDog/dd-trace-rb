# frozen_string_literal: true

RSpec.describe Datadog::Core::Configuration::StableConfig do
  # We cannot test the native lib as it calls libdatadog, which access /etc/datadog-agent
  # System-tests is able to mock these files.
  describe '#extract_configuration' do
    context 'when libdatadog API is not available' do
      it 'returns an empty hash' do
        stub_const('Datadog::Core::LIBDATADOG_API_FAILURE', 'test')
        expect(Datadog.logger).to receive(:debug).with('Cannot enable stable config: test')
        expect(described_class.extract_configuration).to eq({})
      end
    end
  end
end
