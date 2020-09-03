require 'spec_helper'

require_relative 'support/benchmark_helper'

require 'socket'

RSpec.describe 'Microbenchmark Transport' do
  context 'with HTTP transport' do
    # Create server that responds just like the agent,
    # but doesn't consume as many resources, nor introduces external
    # noise into the benchmark.
    let(:server) { TCPServer.new '127.0.0.1', ENV[Datadog::Ext::Transport::HTTP::ENV_DEFAULT_PORT].to_i }

    # Sample agent response, collected from a real agent exchange.
    AGENT_HTTP_RESPONSE = "HTTP/1.1 200\r\n" \
    "Content-Length: 40\r\n" \
    "Content-Type: application/json\r\n" \
    "Date: Thu, 03 Sep 2020 20:05:54 GMT\r\n" \
    "\r\n" \
    "{\"rate_by_service\":{\"service:,env:\":1}}\n".freeze

    before(:each) do
      @server_thread = Thread.new do
        previous_conn = nil
        loop do
          conn = server.accept
          conn.print AGENT_HTTP_RESPONSE
          conn.flush

          # Closing the connection immediately can sometimes
          # be too fast, cause to other side to not be able
          # to read the response in time.
          # We instead delay closing the connection until the next
          # connection request comes in.
          previous_conn.close if previous_conn
          previous_conn = conn
        end
      end
    end

    after(:each) do
      @server_thread.kill
    end

    around do |example|
      # Set the agent port used by the default HTTP transport
      ClimateControl.modify(Datadog::Ext::Transport::HTTP::ENV_DEFAULT_PORT => available_port.to_s) do
        example.run
      end
    end

    describe 'send_traces' do
      include_examples 'benchmark'

      let(:transport) { Datadog::Transport::HTTP.default }

      # Test with with up to 1000 spans being flushed
      # in a single method call. This would translate to
      # up to 1000 spans per second in a real application.
      let(:steps) { [1, 10, 100, 1000] }

      let(:span1) { get_test_traces(1) }
      let(:span10) { get_test_traces(10) }
      let(:span100) { get_test_traces(100) }
      let(:span1000) { get_test_traces(1000) }
      let(:span) { { 1 => span1, 10 => span10, 100 => span100, 1000 => span1000 } }

      # Remove objects created during specs from memory results
      let(:ignore_files) { %r{(/spec/)} }

      def subject(i)
        transport.send_traces(span[i])
      end
    end
  end
end
