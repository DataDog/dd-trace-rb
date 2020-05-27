require 'spec_helper'

require 'ddtrace/transport/io/client'
require 'ddtrace/profiling/transport/io/client'

RSpec.describe Datadog::Profiling::Transport::IO::Client do
  subject(:client) do
    Datadog::Transport::IO::Client.new(out, encoder).tap do |client|
      client.extend(described_class)
    end
  end

  let(:out) { instance_double(IO) }
  let(:encoder) { instance_double(Datadog::Encoding::Encoder) }

  describe '#send_flushes' do
    context 'given events' do
      subject(:send_flushes) { client.send_flushes(events) }
      let(:events) { instance_double(Array) }
      let(:encoded_events) { double('encoded events') }
      let(:result) { double('IO result') }

      before do
        expect(client.encoder).to receive(:encode)
          .with(events)
          .and_return(encoded_events)

        expect(client.out).to receive(:puts)
          .with(encoded_events)
          .and_return(result)

        expect(client).to receive(:update_stats_from_response!)
          .with(kind_of(Datadog::Profiling::Transport::IO::Response))
      end

      it do
        is_expected.to be_a_kind_of(Datadog::Profiling::Transport::IO::Response)
        expect(send_flushes.result).to eq(result)
      end
    end

    context 'given events and a block' do
      subject(:send_flushes) { client.send_flushes(events) { |out, data| target.write(out, data) } }
      let(:events) { instance_double(Array) }
      let(:encoded_events) { double('encoded events') }
      let(:result) { double('IO result') }
      let(:target) { double('target') }

      before do
        expect(client.encoder).to receive(:encode)
          .with(events)
          .and_return(encoded_events)

        expect(target).to receive(:write)
          .with(client.out, encoded_events)
          .and_return(result)

        expect(client).to receive(:update_stats_from_response!)
          .with(kind_of(Datadog::Profiling::Transport::IO::Response))
      end

      it do
        is_expected.to be_a_kind_of(Datadog::Profiling::Transport::IO::Response)
        expect(send_flushes.result).to eq(result)
      end
    end
  end
end
