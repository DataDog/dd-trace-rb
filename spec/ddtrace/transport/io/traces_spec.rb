require 'spec_helper'

require 'ddtrace/transport/io/traces'

RSpec.describe Datadog::Transport::IO::Client do
  subject(:client) { described_class.new(out, encoder) }
  let(:out) { instance_double(IO) }
  let(:encoder) { instance_double(Datadog::Encoding::Encoder) }

  describe '#send_traces' do
    context 'given traces' do
      subject(:send_traces) { client.send_traces(traces) }
      let(:traces) { instance_double(Array, count: 123) }
      let(:encoded_traces) { double('encoded traces') }
      let(:result) { double('IO result') }

      before do
        expect(client.encoder).to receive(:encode)
          .with(traces)
          .and_return(encoded_traces)

        expect(client.out).to receive(:puts)
          .with(encoded_traces)
          .and_return(result)

        expect(client).to receive(:update_stats_from_response!)
          .with(kind_of(Datadog::Transport::IO::Traces::Response))
      end

      it do
        is_expected.to be_a_kind_of(Datadog::Transport::IO::Traces::Response)
        expect(send_traces.result).to eq(result)
      end
    end

    context 'given traces and a block' do
      subject(:send_traces) { client.send_traces(traces) { |out, data| target.write(out, data) } }
      let(:traces) { instance_double(Array, count: 123) }
      let(:encoded_traces) { double('encoded traces') }
      let(:result) { double('IO result') }
      let(:target) { double('target') }

      before do
        expect(client.encoder).to receive(:encode)
          .with(traces)
          .and_return(encoded_traces)

        expect(target).to receive(:write)
          .with(client.out, encoded_traces)
          .and_return(result)

        expect(client).to receive(:update_stats_from_response!)
          .with(kind_of(Datadog::Transport::IO::Traces::Response))
      end

      it do
        is_expected.to be_a_kind_of(Datadog::Transport::IO::Traces::Response)
        expect(send_traces.result).to eq(result)
      end
    end
  end
end
