require 'spec_helper'

require 'ddtrace/transport/io/client'

RSpec.describe Datadog::Transport::IO::Client do
  subject(:client) { described_class.new(out, encoder) }
  let(:out) { instance_double(IO) }
  let(:encoder) { instance_double(Datadog::Encoding::Encoder) }

  describe '#initialize' do
    it { is_expected.to be_a_kind_of Datadog::Transport::Statistics }

    it 'has the correct default properties' do
      is_expected.to have_attributes(
        out: out,
        encoder: encoder
      )
    end
  end

  describe '#send_request' do
    context 'given a request' do
      subject(:send_request) { client.send_request(request) }

      let(:request) { instance_double(Datadog::Transport::Request, parcel: parcel) }
      let(:parcel) { instance_double(Datadog::Transport::Parcel, data: data) }
      let(:data) { 'Hello, world!' }
      let(:encoded_data) { double('encoded data') }
      let(:bytes_written) { data.bytesize }

      before do
        expect(client.encoder).to receive(:encode)
          .with(data)
          .and_return(encoded_data)

        expect(client.out).to receive(:write)
          .with(encoded_data)
          .and_return(bytes_written)

        expect(client).to receive(:update_stats_from_response!)
          .with(kind_of(Datadog::Transport::IO::Response))

        send_request
      end

      it do
        is_expected.to be_a_kind_of(Datadog::Transport::IO::Response)
        expect(send_request.bytes_written).to eq(bytes_written)
      end
    end

    context 'given a request and block' do
      subject(:send_request) do
        client.send_request(request) do |out, request|
          expect(out).to be(client.out)
          expect(request).to be(request)
          response
        end
      end

      let(:request) { instance_double(Datadog::Transport::Request) }
      let(:response) { instance_double(Datadog::Transport::IO::Response) }

      before do
        expect(client).to receive(:update_stats_from_response!)
          .with(response)

        send_request
      end

      it do
        is_expected.to be response
      end
    end
  end
end
