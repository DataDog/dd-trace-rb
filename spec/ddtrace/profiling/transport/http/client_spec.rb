require 'spec_helper'

require 'ddtrace'
require 'ddtrace/transport/http/client'

RSpec.describe Datadog::Profiling::Transport::HTTP::Client do
  subject(:client) { described_class.new(api) }

  let(:api) { instance_double(Datadog::Profiling::Transport::HTTP::API::Instance) }

  describe '#initialize' do
    it { is_expected.to be_a_kind_of(Datadog::Transport::HTTP::Client) }
    it { is_expected.to be_a_kind_of(Datadog::Profiling::Transport::Client) }
    it { is_expected.to be_a_kind_of(Datadog::Transport::HTTP::Statistics) }
    it { is_expected.to have_attributes(api: api) }
  end

  shared_context 'HTTP request' do
    let(:response) { instance_double(Datadog::Profiling::Transport::HTTP::Response, code: double('status code')) }

    before do
      expect(api).to receive(:send_profiling_flush)
        .with(kind_of(Datadog::Transport::HTTP::Env))
        .and_return(response)

      expect(client).to receive(:update_stats_from_response!)
        .with(response)
    end
  end

  describe '#send_profiling_flush' do
    include_context 'HTTP request'

    subject(:send_profiling_flush) { client.send_profiling_flush(flush) }

    let(:flush) { instance_double(Datadog::Profiling::Flush) }

    context 'when request was successful' do
      before do
        allow(response).to receive(:ok?).and_return(true)
      end

      it 'returns the response object' do
        is_expected.to be response
      end

      it 'debug logs the successful report' do
        expect(Datadog.logger).to receive(:debug).with(/Success/)

        send_profiling_flush
      end
    end

    context 'when request was not successful' do
      before do
        allow(response).to receive(:ok?).and_return(nil)
      end

      it 'returns the response object' do
        is_expected.to be response
      end

      it 'debug logs the failed report' do
        expect(Datadog.logger).to receive(:debug) { |&block| expect(block.call).to match(/Fail/) }

        send_profiling_flush
      end
    end
  end

  describe '#send_payload' do
    include_context 'HTTP request'

    subject(:send_payload) { client.send_payload(request) }

    let(:request) { instance_double(Datadog::Profiling::Transport::Request) }

    it 'returns the response object' do
      is_expected.to be response
    end
  end
end
