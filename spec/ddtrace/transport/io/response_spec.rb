require 'spec_helper'

require 'ddtrace/transport/io/response'

RSpec.describe Datadog::Transport::IO::Response do
  context 'when implemented by a class' do
    subject(:response) { described_class.new(result, trace_count) }
    let(:result) { double('result') }
    let(:trace_count) { 1 }

    describe '#result' do
      subject(:get_result) { response.result }
      it { is_expected.to eq result }
    end

    describe '#trace_count' do
      subject(:get_trace_count) { response.trace_count }
      it { is_expected.to eq trace_count }
    end

    describe '#ok?' do
      subject(:ok?) { response.ok? }
      it { is_expected.to be true }
    end
  end
end
