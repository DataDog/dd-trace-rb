# frozen_string_literal: true

require 'datadog'
require 'datadog/tracing/distributed/propagation_policy'

RSpec.describe Datadog::Tracing::Distributed::PropagationPolicy do
  describe '#enabled?' do
    context 'when tracing is disabled' do
      before do
        allow(Datadog::Tracing).to receive(:enabled?).and_return(false)
      end

      it { expect(described_class.enabled?).to be false }
    end

    context 'when appsec standalone is enabled' do
      context 'when there is no active trace' do
        before do
          allow(Datadog.configuration.apm.tracing).to receive(:enabled).and_return(false)
        end

        let(:result) do
          described_class.enabled?(
            global_config: { distributed_tracing: true }
          )
        end

        it { expect(result).to be false }
      end

      context 'when there is an active trace' do
        context 'when appsec is disabled' do
          let(:trace) { instance_double(Datadog::Tracing::TraceOperation) }

          let(:result) do
            described_class.skip?(
              trace: trace
            )
          end

          it { expect(result).to be false }
        end

        context 'when the active trace has no distributed appsec event' do
          before do
            allow(Datadog.configuration.apm.tracing).to receive(:enabled).and_return(false)
            allow(Datadog.configuration.appsec).to receive(:enabled).and_return(true)
            allow(trace).to receive(:get_tag).with('_dd.p.ts').and_return(nil)
          end

          let(:trace) { instance_double(Datadog::Tracing::TraceOperation) }

          let(:result) do
            described_class.enabled?(
              global_config: { distributed_tracing: true },
              trace: trace
            )
          end

          it { expect(result).to be false }
        end

        context 'when the active trace has a distributed appsec event' do
          before do
            allow(Datadog.configuration.apm.tracing).to receive(:enabled).and_return(false)
            allow(Datadog.configuration.appsec).to receive(:enabled).and_return(true)
            allow(trace).to receive(:get_tag).with('_dd.p.ts').and_return('02')
          end

          let(:trace) { instance_double(Datadog::Tracing::TraceOperation) }

          let(:result) do
            described_class.enabled?(
              global_config: { distributed_tracing: true },
              trace: trace
            )
          end

          it { expect(result).to be true }
        end
      end
    end

    context 'when distributed tracing in global config is enabled' do
      let(:result) do
        described_class.skip?(
          global_config: { distributed_tracing: true }
        )
      end

      it { expect(result).to be false }
    end

    context 'when distributed tracing in global config is disabled' do
      let(:result) do
        described_class.skip?(
          global_config: { distributed_tracing: false }
        )
      end

      it { expect(result).to be true }
    end

    context 'when distributed tracing in pin_config is disabled' do
      let(:result) do
        described_class.enabled?(
          pin_config: Datadog::Core::Pin.new(distributed_tracing: false)
        )
      end

      it { expect(result).to be true }
    end

    context 'when distributed tracing in pin_config is enabled' do
      let(:result) do
        described_class.skip?(
          pin_config: Datadog::Core::Pin.new(distributed_tracing: true)
        )
      end

      it { expect(result).to be false }
    end
  end
end
