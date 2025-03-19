# frozen_string_literal: true

require 'datadog'
require 'datadog/tracing/distributed/skip_policy'

RSpec.describe Datadog::Tracing::Distributed::SkipPolicy do
  describe '#skip?' do
    context 'when distributed tracing in datadog_config is enabled' do
      let(:result) do
        described_class.skip?(
          global_config: { distributed_tracing: true }
        )
      end

      it { expect(result).to be false }
    end

    context 'when distributed tracing in datadog_config is disabled' do
      let(:result) do
        described_class.skip?(
          global_config: { distributed_tracing: false }
        )
      end

      it { expect(result).to be true }
    end

    context 'when appsec standalone is enabled' do
      context 'when there is no active trace' do
        before do
          allow(Datadog.configuration.appsec.standalone).to receive(:enabled).and_return(true)
        end

        let(:result) do
          described_class.skip?(
            global_config: { distributed_tracing: true }
          )
        end

        it { expect(result).to be true }
      end

      context 'when there is an active trace' do
        context 'when the active trace has no distributed appsec event' do
          before do
            allow(Datadog.configuration.appsec.standalone).to receive(:enabled).and_return(true)
            allow(trace).to receive(:get_tag).with('_dd.p.appsec').and_return(nil)
          end

          let(:trace) { instance_double(Datadog::Tracing::TraceOperation) }

          let(:result) do
            described_class.skip?(
              global_config: { distributed_tracing: true },
              trace: trace
            )
          end

          it { expect(result).to be true }
        end

        context 'when the active trace has a distributed appsec event' do
          before do
            allow(Datadog.configuration.appsec.standalone).to receive(:enabled).and_return(true)
            allow(trace).to receive(:get_tag).with('_dd.p.appsec').and_return('1')
          end

          let(:trace) { instance_double(Datadog::Tracing::TraceOperation) }

          let(:result) do
            described_class.skip?(
              global_config: { distributed_tracing: true },
              trace: trace
            )
          end

          it { expect(result).to be false }
        end
      end
    end

    context 'given a client config with distributed_tracing disabled' do
      let(:result) do
        described_class.skip?(
          pin_config: Datadog::Core::Pin.new(distributed_tracing: false)
        )
      end

      it { expect(result).to be true }
    end

    context 'given a client config with distributed_tracing enabled' do
      let(:result) do
        described_class.skip?(
          pin_config: Datadog::Core::Pin.new(distributed_tracing: true)
        )
      end

      it { expect(result).to be false }
    end
  end
end
