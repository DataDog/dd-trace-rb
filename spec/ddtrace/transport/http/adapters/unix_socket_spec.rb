require 'spec_helper'

require 'ddtrace/transport/http/adapters/unix_socket'

RSpec.describe Datadog::Transport::HTTP::Adapters::UnixSocket do
  subject(:adapter) { described_class.new(filepath, options) }

  let(:filepath) { double('filepath') }
  let(:timeout) { double('timeout') }
  let(:options) { { timeout: timeout } }

  shared_context 'HTTP connection stub' do
    let(:http_connection) { instance_double(described_class::HTTP) }

    before do
      allow(described_class::HTTP).to receive(:new)
        .with(
          adapter.filepath,
          read_timeout: timeout,
          continue_timeout: timeout
        )
        .and_return(http_connection)

      allow(http_connection).to receive(:start) do |&block|
        block.call(http_connection)
      end
    end
  end

  describe '#initialize' do
    context 'given no options' do
      let(:options) { {} }

      it do
        is_expected.to have_attributes(
          filepath: filepath,
          timeout: described_class::DEFAULT_TIMEOUT
        )
      end
    end

    context 'given a timeout option' do
      let(:options) { { timeout: timeout } }
      let(:timeout) { double('timeout') }
      it { is_expected.to have_attributes(timeout: timeout) }
    end
  end

  describe '#open' do
    include_context 'HTTP connection stub'

    it 'opens and yields a Net::HTTP connection' do
      expect { |b| adapter.open(&b) }.to yield_with_args(http_connection)
    end
  end

  describe '#url' do
    subject(:url) { adapter.url }

    let(:filepath) { '/tmp/trace.sock' }
    let(:timeout) { 7 }
    it { is_expected.to eq('http+unix:///tmp/trace.sock?timeout=7') }
  end
end

RSpec.describe Datadog::Transport::HTTP::Adapters::UnixSocket::HTTP do
  subject(:unix_http) { described_class.new(filepath, options) }
  let(:filepath) { double('filepath') }
  let(:options) { {} }

  describe '#initialize' do
    context 'given no options' do
      let(:options) { {} }

      it do
        is_expected.to have_attributes(
          filepath: filepath,
          read_timeout: described_class::DEFAULT_TIMEOUT,
          continue_timeout: described_class::DEFAULT_TIMEOUT
        )
      end
    end

    context 'given a read timeout option' do
      let(:options) { { read_timeout: read_timeout } }
      let(:read_timeout) { double('read_timeout') }
      it { is_expected.to have_attributes(read_timeout: read_timeout) }
    end

    context 'given a continue timeout option' do
      let(:options) { { continue_timeout: continue_timeout } }
      let(:continue_timeout) { double('continue_timeout') }
      it { is_expected.to have_attributes(continue_timeout: continue_timeout) }
    end
  end

  describe '#connect' do
    subject(:connect) { unix_http.connect }
    let(:unix_socket) { instance_double(::UNIXSocket) }
    let(:net_io) { instance_double(::Net::BufferedIO) }

    before do
      allow(::UNIXSocket).to receive(:open)
        .with(filepath)
        .and_return(unix_socket)

      allow(::Net::BufferedIO).to receive(:new)
        .with(unix_socket)
        .and_return(net_io)

      allow(net_io).to receive(:read_timeout=)
      allow(net_io).to receive(:continue_timeout=)
      allow(net_io).to receive(:debug_output=)
    end

    it 'opens a Unix socket' do
      expect { connect }.to change { unix_http.unix_socket }.from(nil).to(unix_socket)
      expect(net_io).to have_received(:read_timeout=).with(unix_http.read_timeout)
      expect(net_io).to have_received(:continue_timeout=).with(unix_http.continue_timeout)
    end
  end
end
