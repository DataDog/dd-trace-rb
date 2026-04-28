require 'datadog/tracing/contrib/rack/configuration/settings'

RSpec.describe Datadog::Tracing::Contrib::Rack::Configuration::Settings do
  describe '#use_events' do
    subject(:use_events) { described_class.new.use_events }

    context 'when default' do
      it { is_expected.to be false }
    end

    context 'when configured via environment variable' do
      around do |example|
        ClimateControl.modify('DD_TRACE_RACK_USE_EVENTS' => 'true') do
          example.run
        end
      end

      it { is_expected.to be true }
    end
  end

  describe '#distributed_tracing' do
    subject(:distributed_tracing) { described_class.new.distributed_tracing }

    context 'when default' do
      it { is_expected.to be true }
    end

    context 'when configured via environment variable' do
      around do |example|
        ClimateControl.modify('DD_TRACE_RACK_DISTRIBUTED_TRACING' => 'false') do
          example.run
        end
      end

      it { is_expected.to be false }
    end
  end
end
