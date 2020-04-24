require 'spec_helper'

require 'ddtrace/profiling/exporter'

RSpec.describe Datadog::Profiling::Exporter do
  subject(:exporter) { described_class.new(transport) }
  let(:transport) { double('transport') }

  describe '::new' do
    context 'given an IO transport' do
      let(:transport) { Datadog::Transport::IO::Client.new(out, encoder) }
      let(:out) { instance_double(IO) }
      let(:encoder) { instance_double(Datadog::Encoding::Encoder) }

      it 'extends the transport with profiling behavior' do
        is_expected.to have_attributes(
          transport: a_kind_of(Datadog::Profiling::Transport::IO::Client)
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
end
