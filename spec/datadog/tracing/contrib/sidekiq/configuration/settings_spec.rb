require 'datadog/tracing/contrib/sidekiq/configuration/settings'
require 'datadog/tracing/contrib/shared_settings_examples'

RSpec.describe Datadog::Tracing::Contrib::Sidekiq::Configuration::Settings do
  it_behaves_like 'with on_error setting'

  describe '#distributed_tracing' do
    subject(:distributed_tracing) { described_class.new.distributed_tracing }

    context 'when default' do
      it { is_expected.to be false }
    end

    context 'when configured via environment variable' do
      around do |example|
        ClimateControl.modify('DD_TRACE_SIDEKIQ_DISTRIBUTED_TRACING' => 'true') do
          example.run
        end
      end

      it { is_expected.to be true }
    end
  end
end
