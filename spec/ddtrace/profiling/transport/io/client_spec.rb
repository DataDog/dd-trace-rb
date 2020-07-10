require 'spec_helper'

require 'ddtrace/profiling/flush'
require 'ddtrace/profiling/transport/io/client'

RSpec.describe Datadog::Profiling::Transport::IO::Client do
  subject(:client) { described_class.new(out, encoder) }
  let(:out) { instance_double(IO) }
  let(:encoder) { instance_double(Datadog::Encoding::Encoder) }

  describe '#send_profiling_flush' do
    subject(:send_profiling_flush) { client.send_profiling_flush(flush) }

    let(:flush) { instance_double(Datadog::Profiling::Flush) }
    let(:encoded_events) { double('encoded events') }
    let(:result) { double('IO result') }

    before do
      expect(client.encoder).to receive(:encode)
        .with(flush)
        .and_return(encoded_events)

      expect(client.out).to receive(:puts)
        .with(encoded_events)
        .and_return(result)

      expect(client).to receive(:update_stats_from_response!)
        .with(kind_of(Datadog::Profiling::Transport::IO::Response))
    end

    it do
      is_expected.to be_a_kind_of(Datadog::Profiling::Transport::IO::Response)
      expect(send_profiling_flush.result).to eq(result)
    end
  end

  describe '#build_response' do
    subject(:build_response) { client.build_response(request, data, result) }
    let(:request) { instance_double(Datadog::Profiling::Transport::Request) }
    let(:data) { double('data') }
    let(:result) { double('result') }
    let(:response) { instance_double(Datadog::Profiling::Transport::IO::Response) }

    before do
      expect(Datadog::Profiling::Transport::IO::Response)
        .to receive(:new)
        .with(result)
        .and_return(response)
    end

    it { is_expected.to be response }
  end
end
