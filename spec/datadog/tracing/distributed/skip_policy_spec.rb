# frozen_string_literal: true

require 'datadog'
require 'datadog/tracing/distributed/skip_policy'

RSpec.describe Datadog::Tracing::Distributed::SkipPolicy do
  describe '#skip?' do
    context 'when asm tracing is disabled' do
      context 'when there is no active trace' do
        before do
          allow(Datadog.configuration.apm.tracing).to receive(:enabled).and_return(false)
        end

        let(:result) do
          described_class.skip?(
            global_config: { distributed_tracing: true }
          )
        end

        it { expect(result).to be true }
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
            described_class.skip?(
              trace: trace
            )
          end

          it { expect(result).to be true }
        end

        context 'when the active trace has a distributed appsec event' do
          before do
            allow(Datadog.configuration.apm.tracing).to receive(:enabled).and_return(false)
            allow(Datadog.configuration.appsec).to receive(:enabled).and_return(true)
            allow(trace).to receive(:get_tag).with('_dd.p.ts').and_return('02')
          end

          let(:trace) { instance_double(Datadog::Tracing::TraceOperation) }

          let(:result) do
            described_class.skip?(
              trace: trace
            )
          end

          it { expect(result).to be false }
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
        described_class.skip?(
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
