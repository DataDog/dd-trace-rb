require 'spec_helper'

require 'ddtrace/transport/io'

RSpec.describe Datadog::Transport::IO do
  describe '.new' do
    subject(:new_io) { described_class.new(out, encoder) }

    let(:out) { instance_double(IO) }
    let(:encoder) { instance_double(Datadog::Core::Encoding::Encoder) }
    let(:client) { instance_double(Datadog::Transport::IO::Client) }

    before do
      expect(Datadog::Transport::IO::Client).to receive(:new)
        .with(out, encoder)
        .and_return(client)
    end

    it { is_expected.to be client }
  end

  describe '.default' do
    let(:client) { instance_double(Datadog::Transport::IO::Client) }

    context 'given no options' do
      subject(:default) { described_class.default }

      before do
        expect(Datadog::Transport::IO::Client).to receive(:new)
          .with($stdout, Datadog::Core::Encoding::JSONEncoder)
          .and_return(client)
      end

      it { is_expected.to be client }
    end

    context 'given overrides' do
      subject(:default) { described_class.default(options) }

      let(:options) { { out: out, encoder: encoder } }
      let(:out) { instance_double(IO) }
      let(:encoder) { instance_double(Datadog::Core::Encoding::Encoder) }

      before do
        expect(Datadog::Transport::IO::Client).to receive(:new)
          .with(out, encoder)
          .and_return(client)
      end

      it { is_expected.to be client }
    end
  end
end
