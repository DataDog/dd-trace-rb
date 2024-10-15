require 'spec_helper'

require 'datadog/tracing/writer'
require 'datadog/tracing/transport/http'
require 'datadog/tracing/transport/http/traces'
require 'datadog/tracing/transport/traces'

RSpec.describe 'Datadog::Tracing::Transport::HTTP integration tests' do
  skip_unless_integration_testing_enabled

  describe 'HTTP#default' do
    subject(:transport) { Datadog::Tracing::Transport::HTTP.default(&client_options) }

    let(:client_options) { proc { |_client| } }

    it { is_expected.to be_a(Datadog::Tracing::Transport::Traces::Transport) }

    describe '#send_traces' do
      subject(:responses) { transport.send_traces(traces) }

      let(:traces) { get_test_traces(2) }

      it do
        is_expected.to all(be_a(Datadog::Tracing::Transport::HTTP::Traces::Response))

        expect(responses).to have(1).item
        response = responses.first
        expect(response.ok?).to be true
        expect(response.service_rates).to_not be nil
      end
    end
  end

  describe Datadog::Tracing::Writer do
    subject(:writer) { described_class.new(writer_options) }

    let(:writer_options) { { transport: client } }
    let(:client) { Datadog::Tracing::Transport::HTTP.default(&client_options) }
    let(:client_options) { proc { |_client| } }

    describe '#send_spans' do
      subject(:send_spans) { writer.send_spans(traces, writer.transport) }

      let(:traces) { get_test_traces(1) }

      it { is_expected.to be true }
    end
  end
end
