require 'datadog/tracing/contrib/karafka/configuration/settings'

RSpec.describe Datadog::Tracing::Contrib::Karafka::Configuration::Settings do
  describe '#distributed_tracing' do
    subject(:distributed_tracing) { described_class.new.distributed_tracing }

    context 'when default' do
      it { is_expected.to be false }
    end

    context 'when configured via environment variable' do
      around do |example|
        ClimateControl.modify('DD_TRACE_KARAFKA_DISTRIBUTED_TRACING' => 'true') do
          example.run
        end
      end

      it { is_expected.to be true }
    end
  end
end
