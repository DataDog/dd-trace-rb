require 'spec_helper'

require 'ddtrace/transport/io/response'

RSpec.describe Datadog::Transport::IO::Response do
  context 'when implemented by a class' do
    subject(:response) { described_class.new(bytes) }
    let(:bytes) { 16 }

    describe '#bytes_written' do
      subject(:bytes_written) { response.bytes_written }
      it { is_expected.to eq bytes }
    end

    describe '#ok?' do
      subject(:ok?) { response.ok? }
      it { is_expected.to be true }
    end
  end
end
