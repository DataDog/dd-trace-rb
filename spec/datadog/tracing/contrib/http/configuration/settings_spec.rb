require 'datadog/tracing/contrib/http/configuration/settings'
require 'datadog/tracing/contrib/service_name_settings_examples'
require 'datadog/tracing/contrib/shared_settings_examples'

RSpec.describe Datadog::Tracing::Contrib::HTTP::Configuration::Settings do
  it_behaves_like 'service name setting', 'net/http'
  it_behaves_like 'with error_status_codes setting', env: 'DD_TRACE_HTTP_ERROR_STATUS_CODES', default: 400...600, settings_class: described_class, option: :error_status_codes

  describe '#distributed_tracing' do
    subject(:distributed_tracing) { described_class.new.distributed_tracing }

    context 'when default' do
      it { is_expected.to be true }
    end

    context 'when configured via environment variable' do
      around do |example|
        ClimateControl.modify('DD_TRACE_HTTP_DISTRIBUTED_TRACING' => 'false') do
          example.run
        end
      end

      it { is_expected.to be false }
    end
  end
end
