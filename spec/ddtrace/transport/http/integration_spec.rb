require 'spec_helper'

require 'ddtrace'
require 'ddtrace/transport/http'

RSpec.describe 'Datadog::Transport::HTTP integration tests' do
  before { skip unless ENV['TEST_DATADOG_INTEGRATION'] }

  describe 'HTTP#default' do
    subject(:transport) { Datadog::Transport::HTTP.default(&client_options) }

    let(:client_options) { proc { |_client| } }

    it { is_expected.to be_a(Datadog::Transport::Traces::Transport) }

    describe '#send_traces' do
      subject(:responses) { transport.send_traces(traces) }

      let(:traces) { get_test_traces(2) }

      it do
        is_expected.to all(be_a(Datadog::Transport::HTTP::Traces::Response))

        expect(responses).to have(1).item
        response = responses.first
        expect(response.ok?).to be true
        expect(response.service_rates).to_not be nil
      end
    end
  end

  describe Datadog::Writer do
    subject(:writer) { described_class.new(writer_options) }

    let(:writer_options) { { transport: client } }
    let(:client) { Datadog::Transport::HTTP.default(&client_options) }
    let(:client_options) { proc { |_client| } }

    describe '#send_spans' do
      subject(:send_spans) { writer.send_spans(traces, writer.transport) }

      let(:traces) { get_test_traces(1) }

      it { is_expected.to be true }

      context 'with priority sampling' do
        let(:writer_options) { super().merge!(priority_sampler: sampler) }
        let(:sampler) { Datadog::PrioritySampler.new }

        # Verify the priority sampler gets updated
        before do
          expect(sampler).to receive(:update)
            .with(kind_of(Hash))
            .and_call_original
        end

        it { is_expected.to be true }
      end
    end
  end
end
