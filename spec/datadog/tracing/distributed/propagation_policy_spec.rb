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

    context 'when apm tracing is disabled' do
      context 'when there is no active trace' do
        before do
          allow(Datadog.configuration.apm.tracing).to receive(:enabled).and_return(false)
        end

        let(:result) { described_class.enabled? }

        it { expect(result).to be false }
      end

      context 'when there is an active trace' do
        context 'when dd.p.ts tag is not set' do
          before do
            allow(Datadog.configuration.apm.tracing).to receive(:enabled).and_return(false)
          end

          let(:trace) { Datadog::Tracing::TraceOperation.new }
          let(:result) { described_class.enabled?(trace: trace) }

          it { expect(result).to be false }
        end

        context 'when there is no distributed appsec event' do
          before do
            allow(Datadog.configuration.apm.tracing).to receive(:enabled).and_return(false)
          end

          let(:trace) { Datadog::Tracing::TraceOperation.new(tags: { '_dd.p.ts' => '01' }) }
          let(:result) { described_class.enabled?(trace: trace) }

          it { expect(result).to be false }
        end

        context 'when there is a distributed appsec event' do
          context 'when appsec is disabled' do
            before do
              allow(Datadog.configuration.apm.tracing).to receive(:enabled).and_return(false)
            end

            let(:trace) { Datadog::Tracing::TraceOperation.new(tags: { '_dd.p.ts' => '02' }) }
            let(:result) { described_class.enabled?(trace: trace) }

            it { expect(result).to be false }
          end

          context 'when appsec is enabled' do
            before do
              allow(Datadog.configuration.apm.tracing).to receive(:enabled).and_return(false)
              allow(Datadog.configuration.appsec).to receive(:enabled).and_return(true)
            end

            let(:trace) { Datadog::Tracing::TraceOperation.new(tags: { '_dd.p.ts' => '02' }) }
            let(:result) { described_class.enabled?(trace: trace) }

            it { expect(result).to be true }
          end
        end
      end
    end

    context 'when distributed tracing in global config is enabled' do
      let(:result) do
        described_class.enabled?(
          global_config: { distributed_tracing: true }
        )
      end

      it { expect(result).to be true }
    end

    context 'when distributed tracing in global config is disabled' do
      let(:result) do
        described_class.enabled?(
          global_config: { distributed_tracing: false }
        )
      end

      it { expect(result).to be false }
    end

    context 'when distributed tracing in pin_config is enabled' do
      let(:result) do
        described_class.enabled?(
          pin_config: Datadog::Core::Pin.new(distributed_tracing: true)
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

      it { expect(result).to be false }
    end
  end
end
