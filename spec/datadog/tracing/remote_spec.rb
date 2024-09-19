require 'spec_helper'

RSpec.describe Datadog::Tracing::Remote do
  let(:remote) { described_class }
  let(:path) { 'datadog/1/APM_TRACING/anything/lib_config' }

  it 'declares the APM_TRACING product' do
    expect(remote.products).to contain_exactly('APM_TRACING')
  end

  it 'declares rule sampling capabilities' do
    expect(remote.capabilities).to contain_exactly(1 << 12, 1 << 13, 1 << 14, 1 << 29)
  end

  it 'declares matches that match APM_TRACING' do
    telemetry = instance_double(Datadog::Core::Telemetry::Component)

    expect(remote.receivers(telemetry)).to all(
      match(
        lambda do |receiver|
          receiver.match? Datadog::Core::Remote::Configuration::Path.parse(path)
        end
      )
    )
  end

  describe '#process_config' do
    subject(:process_config) { remote.process_config(config, content) }
    let(:config) { nil }
    let(:content) { Datadog::Core::Remote::Configuration::Content.parse({ path: path, content: nil }) }

    context 'with an empty content' do
      let(:config) { {} }

      it 'sets errored apply state' do
        process_config
        expect(content.apply_state).to eq(3)
        expect(content.apply_error).to match(/Error/) & match(/in process_config/)
      end
    end

    context 'with a valid content' do
      context 'and nothing configured' do
        let(:config) { { 'lib_config' => {} } }

        it 'sets ok applied state and sends telemetry with empty values' do
          expect(Datadog.send(:components).telemetry).to receive(:client_configuration_change!)
            .with(contain_exactly(
              ['DD_LOGS_INJECTION', nil],
              ['DD_TRACE_HEADER_TAGS', nil],
              ['DD_TRACE_SAMPLE_RATE', nil],
              ['DD_TRACE_SAMPLING_RULES', nil],
            ))

          process_config

          expect(content.apply_state).to eq(2)
          expect(content.apply_error).to be_nil
        end
      end

      context 'and one option configured' do
        let(:config) { { 'lib_config' => { 'log_injection_enabled' => false } } }

        it 'sets ok applied state and sends telemetry with configuration value' do
          expect(Datadog.send(:components).telemetry).to receive(:client_configuration_change!)
            .with(contain_exactly(
              ['DD_LOGS_INJECTION', false],
              ['DD_TRACE_HEADER_TAGS', nil],
              ['DD_TRACE_SAMPLE_RATE', nil],
              ['DD_TRACE_SAMPLING_RULES', nil],
            ))

          process_config

          expect(content.apply_state).to eq(2)
          expect(content.apply_error).to be_nil
        end
      end
    end
  end
end
