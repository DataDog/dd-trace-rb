require 'spec_helper'

require 'ddtrace/transport/io/response'

RSpec.describe Datadog::Transport::IO::Response do
  context 'when implemented by a class' do
    subject(:response) { described_class.new(result) }

    let(:result) { double('result') }

    describe '#result' do
      subject(:get_result) { response.result }

      it { is_expected.to eq result }
    end

    describe '#ok?' do
      subject(:ok?) { response.ok? }

      it { is_expected.to be true }
    end
  end
end
