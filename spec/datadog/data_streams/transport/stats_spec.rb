require 'spec_helper'

require 'datadog/data_streams/transport/stats'
require 'datadog/core/transport/http/client'

RSpec.describe Datadog::DataStreams::Transport::Stats do
  let(:logger) { logger_allowing_debug }

  describe '::Transport' do
    subject(:transport) { described_class::Transport.new(apis, default_api, logger: logger) }

    let(:default_api) { :v01 }
    let(:apis) { {v01: api_instance} }
    let(:api_instance) { instance_double(Datadog::Core::Transport::HTTP::API::Instance) }
    let(:client) { instance_double(Datadog::Core::Transport::HTTP::Client) }

    before do
      allow(Datadog::Core::Transport::HTTP::Client).to receive(:new)
        .with(api_instance, logger: logger)
        .and_return(client)
    end

    describe '#send_stats' do
      subject(:send_stats) { transport.send_stats(payload) }

      let(:payload) do
        {
          'Service' => 'test-service',
          'TracerVersion' => '1.0.0',
          'Lang' => 'ruby',
          'Stats' => [
            {
              'Start' => 1000000000,
              'Duration' => 10000000000,
              'Stats' => [],
              'Backlogs' => []
            }
          ]
        }
      end

      let(:response) { instance_double(Datadog::Core::Transport::HTTP::Response, ok?: true) }

      before do
        allow(client).to receive(:send_request).and_return(response)
      end

      it 'encodes payload with MessagePack' do
        expect(MessagePack).to receive(:pack).with(payload).and_call_original
        send_stats
      end

      it 'compresses the MessagePack data with gzip' do
        expect(Zlib).to receive(:gzip).and_call_original
        send_stats
      end

      it 'sends the compressed data via client' do
        expect(client).to receive(:send_request) do |action, request|
          expect(action).to eq(:stats)
          expect(request).to be_a(Datadog::DataStreams::Transport::Stats::Request)
          expect(request.parcel).to be_a(Datadog::Core::Transport::Parcel)

          # Verify the data is compressed MessagePack
          compressed_data = request.parcel.data
          decompressed = Zlib.gunzip(compressed_data)
          unpacked = MessagePack.unpack(decompressed)
          expect(unpacked).to eq(payload)

          response
        end

        send_stats
      end

      it 'returns the response' do
        expect(send_stats).to eq(response)
      end
    end
  end
end
