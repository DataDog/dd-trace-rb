require 'spec_helper'

require 'ddtrace/transport/io/client'

RSpec.describe Datadog::Transport::IO::Client do
  subject(:client) { described_class.new(out, encoder) }

  let(:out) { instance_double(IO) }
  let(:encoder) { instance_double(Datadog::Core::Encoding::Encoder) }

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
      let(:parcel) { instance_double(Datadog::Transport::IO::Traces::Parcel, data: data) }
      let(:data) { 'Hello, world!' }
      let(:encoded_data) { double('encoded data') }
      let(:result) { double('IO result') }

      before do
        expect(parcel).to receive(:encode_with)
          .with(encoder)
          .and_return(encoded_data)

        expect(client.out).to receive(:puts)
          .with(encoded_data)
          .and_return(result)

        expect(client).to receive(:update_stats_from_response!)
          .with(kind_of(Datadog::Transport::IO::Response))

        send_request
      end

      it do
        is_expected.to be_a_kind_of(Datadog::Transport::IO::Response)
        expect(send_request.result).to eq(result)
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

  describe '#encode_data' do
    subject(:encode_data) { client.encode_data(encoder, request) }

    let(:request) { instance_double(Datadog::Transport::Request, parcel: parcel) }
    let(:parcel) { instance_double(Datadog::Transport::Parcel) }
    let(:data) { double('data') }

    before do
      expect(parcel)
        .to receive(:encode_with)
        .with(encoder)
        .and_return(data)
    end

    it { is_expected.to be data }
  end

  describe '#write_data' do
    subject(:write_data) { client.write_data(out, data) }

    let(:data) { double('data') }
    let(:result) { double('result') }

    before do
      expect(out)
        .to receive(:puts)
        .with(data)
        .and_return(result)
    end

    it { is_expected.to be result }
  end

  describe '#build_response' do
    subject(:build_response) { client.build_response(request, data, result) }

    let(:request) { instance_double(Datadog::Transport::Request) }
    let(:data) { double('data') }
    let(:result) { double('result') }
    let(:response) { instance_double(Datadog::Transport::IO::Response) }

    before do
      expect(Datadog::Transport::IO::Response)
        .to receive(:new)
        .with(result)
        .and_return(response)
    end

    it { is_expected.to be response }
  end
end
