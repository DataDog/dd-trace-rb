require 'datadog/tracing/contrib/support/spec_helper'

# Load integrations so they're available
%w[
  ethon
  excon
  faraday
  grpc
  rest_client
].each do |integration|
  begin
    require integration
  rescue LoadError
    # If library isn't available, it can't be instrumented.
  end
end

require 'datadog/tracing'
require 'datadog/tracing/tracer'
require 'ddtrace/transport/http'
require 'ddtrace/transport/io'

# Tests that combine the core library with integrations,
# whose examples don't belong exclusively to either.
RSpec.describe 'transport with integrations' do
  describe 'when sending traces' do
    before do
      Datadog.configure do |c|
        # Activate all outbound integrations...
        # Although the transport by default only uses Net/HTTP
        # its possible for other adapters to be used instead.
        c.tracing.instrument :ethon
        c.tracing.instrument :excon
        c.tracing.instrument :faraday
        c.tracing.instrument :grpc
        c.tracing.instrument :http
        c.tracing.instrument :rest_client
      end

      # Requests may produce an error (because the transport cannot connect)
      # but ignore this... we just need requests, not a successful response.
      allow(Datadog.logger).to receive(:error)
    end

    shared_examples_for 'an uninstrumented transport' do
      before do
        expect_any_instance_of(Datadog::Tracing::Tracer).to_not receive(:trace)
        expect_any_instance_of(Datadog::Tracing::Tracer).to_not receive(:start_span)
      end

      describe '#send_traces' do
        subject(:send_traces) { transport.send_traces(traces) }

        let(:traces) { get_test_traces(1) }

        it 'does not produce traces for itself' do
          send_traces
        end
      end
    end

    context 'given the default transport' do
      let(:transport) { Datadog::Transport::HTTP.default }

      it_behaves_like 'an uninstrumented transport'
    end

    context 'given an Unix socket transport' do
      let(:transport) do
        Datadog::Transport::HTTP.default do |t|
          t.adapter :unix, '/tmp/ddagent/trace.sock'
        end
      end

      it_behaves_like 'an uninstrumented transport'
    end

    context 'given an IO transport' do
      let(:transport) { Datadog::Transport::IO.default(out: out) }
      let(:out) { instance_double(::IO) }

      before { allow(out).to receive(:puts) }

      it_behaves_like 'an uninstrumented transport'
    end
  end
end
