require 'datadog/tracing/contrib/que/configuration/settings'
require 'datadog/tracing/contrib/shared_settings_examples'

RSpec.describe Datadog::Tracing::Contrib::Que::Configuration::Settings do
  it_behaves_like 'with on_error setting'

  describe '#distributed_tracing' do
    subject(:distributed_tracing) { described_class.new.distributed_tracing }

    context 'when default' do
      it { is_expected.to be true }
    end

    context 'when configured via environment variable' do
      around do |example|
        ClimateControl.modify('DD_TRACE_QUE_DISTRIBUTED_TRACING' => 'false') do
          example.run
        end
      end

      it { is_expected.to be false }
    end
  end
end
