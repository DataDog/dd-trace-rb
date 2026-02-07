require 'spec_helper'

require 'datadog/tracing/transport/io/client'
require 'datadog/tracing/transport/io/traces'

RSpec.describe Datadog::Tracing::Transport::IO::Client do
  subject(:client) { described_class.new(out, encoder) }

  let(:out) { instance_double(IO) }
  let(:encoder) { instance_double(Datadog::Core::Encoding::Encoder) }

  describe '#initialize' do
    it { is_expected.to be_a_kind_of Datadog::Tracing::Transport::Statistics }

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

      let(:request) { instance_double(Datadog::Core::Transport::Request, parcel: parcel) }
      let(:parcel) { instance_double(Datadog::Core::Transport::Parcel, data: data) }
      let(:data) { 'Hello, world!' }
      let(:result) { double('IO result') }

      before do
        expect(client.out).to receive(:puts)
          .with(data)
          .and_return(result)

        expect(client).to receive(:update_stats_from_response!)
          .with(kind_of(Datadog::Tracing::Transport::IO::Response))

        send_request
      end

      it do
        is_expected.to be_a_kind_of(Datadog::Tracing::Transport::IO::Response)
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

      let(:request) { instance_double(Datadog::Core::Transport::Request) }
      let(:response) { instance_double(Datadog::Tracing::Transport::IO::Response) }

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

    let(:request) { instance_double(Datadog::Core::Transport::Request) }
    let(:data) { double('data') }
    let(:result) { double('result') }
    let(:response) { instance_double(Datadog::Tracing::Transport::IO::Response) }

    before do
      expect(Datadog::Tracing::Transport::IO::Response)
        .to receive(:new)
        .with(result)
        .and_return(response)
    end

    it { is_expected.to be response }
  end

  describe '#send_traces' do
    context 'given traces' do
      subject(:send_traces) { client.send_traces(traces) }

      let(:traces) { get_test_traces(2) }
      let(:result) { double('IO result') }

      before do
        # Mock only the IO operation - let encoding happen naturally
        expect(client.out).to receive(:puts)
          .with(kind_of(String))
          .and_return(result)

        expect(client).to receive(:update_stats_from_response!)
          .with(kind_of(Datadog::Tracing::Transport::IO::Traces::Response))
      end

      it do
        is_expected.to all(be_a(Datadog::Tracing::Transport::IO::Traces::Response))
        expect(send_traces.first.result).to eq(result)
      end
    end

    context 'given traces and a block' do
      subject(:send_traces) { client.send_traces(traces) { |out, data| target.write(out, data) } }

      let(:traces) { get_test_traces(2) }
      let(:result) { double('IO result') }
      let(:target) { double('target') }

      before do
        # Mock only the custom write operation - let encoding happen naturally
        expect(target).to receive(:write)
          .with(client.out, kind_of(String))
          .and_return(result)

        expect(client).to receive(:update_stats_from_response!)
          .with(kind_of(Datadog::Tracing::Transport::IO::Traces::Response))
      end

      it do
        is_expected.to all(be_a(Datadog::Tracing::Transport::IO::Traces::Response))
        expect(send_traces.first.result).to eq(result)
      end
    end
  end
end
