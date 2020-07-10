require 'spec_helper'

require 'ddtrace/profiling/exporter'
require 'ddtrace/profiling/flush'
require 'ddtrace/profiling/transport/io'

RSpec.describe Datadog::Profiling::Exporter do
  subject(:exporter) { described_class.new(transport) }
  let(:transport) { Datadog::Profiling::Transport::IO.default }

  describe '::new' do
    context 'given an IO transport' do
      it 'uses the transport' do
        is_expected.to have_attributes(
          transport: transport
        )
      end
    end

    context 'given an HTTP transport' do
      let(:transport) { instance_double(Datadog::Transport::HTTP::Client) }

      # TODO: Should not raise an error when implemented.
      it 'raises an error' do
        expect { exporter }.to raise_error(ArgumentError)
      end
    end
  end

  describe '#export' do
    subject(:export) { exporter.export(flush) }
    let(:flush) { instance_double(Datadog::Profiling::Flush) }
    let(:result) { double('result') }

    before do
      allow(transport)
        .to receive(:send_profiling_flush)
        .and_return(result)
    end

    it do
      is_expected.to be result

      expect(transport)
        .to have_received(:send_profiling_flush)
        .with(flush)
    end
  end
end
