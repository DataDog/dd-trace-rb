require 'spec_helper'

require 'ddtrace/profiling/transport/io'

RSpec.describe Datadog::Profiling::Transport::IO do
  describe '.new' do
    subject(:new_io) { described_class.new(out, encoder, options) }
    let(:out) { instance_double(IO) }
    let(:encoder) { double('encoder') }
    let(:options) { {} }
    let(:client) { instance_double(Datadog::Profiling::Transport::IO::Client) }

    before do
      expect(Datadog::Profiling::Transport::IO::Client).to receive(:new)
        .with(out, encoder, options)
        .and_return(client)
    end

    it { is_expected.to be client }
  end

  describe '.default' do
    let(:client) { instance_double(Datadog::Profiling::Transport::IO::Client) }

    context 'given no options' do
      subject(:default) { described_class.default }

      before do
        expect(Datadog::Profiling::Transport::IO::Client).to receive(:new)
          .with(STDOUT, Datadog::Profiling::Encoding::Profile::Protobuf, {})
          .and_return(client)
      end

      it { is_expected.to be client }
    end

    context 'given overrides' do
      subject(:default) { described_class.default(options) }
      let(:options) { { out: out, encoder: encoder, custom_option: 'custom_option' } }
      let(:out) { instance_double(IO) }
      let(:encoder) { double('encoder') }

      before do
        expect(Datadog::Profiling::Transport::IO::Client).to receive(:new)
          .with(out, encoder, custom_option: 'custom_option')
          .and_return(client)
      end

      it { is_expected.to be client }
    end
  end
end
