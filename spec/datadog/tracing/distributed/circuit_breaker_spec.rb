require 'datadog'
require 'datadog/tracing/distributed/circuit_breaker'

RSpec.describe Datadog::Tracing::Distributed::CircuitBreaker do
  subject(:circuit_breaker) { circuit_breaker_class.new }

  let(:circuit_breaker_class) { Class.new { include Datadog::Tracing::Distributed::CircuitBreaker } }

  describe '#should_skip_distributed_tracing?' do
    subject(:should_skip_distributed_tracing?) do
      circuit_breaker.send(
        :should_skip_distributed_tracing?,
        **{ client_config: client_config, datadog_config: datadog_config, trace: trace }
      )
    end

    let(:client_config) { nil }
    let(:datadog_config) { { distributed_tracing: true } }
    let(:appsec_standalone) { false }
    let(:trace) { nil }
    let(:distributed_appsec_event) { nil }

    before do
      allow(Datadog.configuration.appsec.standalone).to receive(:enabled).and_return(appsec_standalone)
      allow(trace).to receive(:get_tag).with('_dd.p.appsec').and_return(distributed_appsec_event) if trace
    end

    context 'when distributed tracing in datadog_config is enabled' do
      it { is_expected.to be false }
    end

    context 'when distributed tracing in datadog_config is disabled' do
      let(:datadog_config) { { distributed_tracing: false } }

      it { is_expected.to be true }
    end

    context 'when appsec standalone is enabled' do
      let(:appsec_standalone) { true }

      context 'when there is no active trace' do
        it { is_expected.to be true }
      end

      context 'when there is an active trace' do
        let(:trace) { instance_double(Datadog::Tracing::TraceOperation) }

        context 'when the active trace has no distributed appsec event' do
          it { is_expected.to be true }
        end

        context 'when the active trace has a distributed appsec event' do
          # This should act like standalone appsec is disabled, as it does not return in the
          # `if Datadog.configuration.appsec.standalone.enabled` block
          # so we're only testing the "no client config, distributed tracing enabled" case here
          let(:distributed_appsec_event) { '1' }

          it { is_expected.to be false }
        end
      end
    end

    context 'given a client config with distributed_tracing disabled' do
      let(:client_config) { { distributed_tracing: false } }

      it { is_expected.to be true }
    end

    context 'given a client config with distributed_tracing enabled' do
      let(:client_config) { { distributed_tracing: true } }

      it { is_expected.to be false }
    end
  end
end
