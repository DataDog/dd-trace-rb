require 'spec_helper'

require 'benchmark'
require 'ddtrace'
require 'ddtrace/transport/http'

RSpec.describe 'Transport::HTTP benchmarks' do
  let(:iterations) { 100 }

  before { skip('Performance test does not run in CI.') }

  describe '#send' do
    let!(:default_transport) { Datadog::Transport::HTTP.default }
    let!(:net_transport) { Datadog::Transport::HTTP.default { |t| t.adapter :net_http } }
    let!(:unix_transport) { Datadog::Transport::HTTP.default { |t| t.adapter :unix } }
    let!(:test_transport) { Datadog::Transport::HTTP.default { |t| t.adapter :test } }

    let!(:traces) { get_test_traces(2) }

    it do
      Benchmark.bm do |x|
        x.report('Default Datadog::Transport::HTTP') do
          iterations.times do
            default_transport.send_traces(traces)
          end
        end

        x.report('Datadog::Transport::HTTP with Net::HTTP adapter') do
          iterations.times do
            net_transport.send_traces(traces)
          end
        end

        # TODO: Enable me when Unix socket support for Datadog agent is released in 6.13.
        #       Then update the agent configuration for the test suite to enable Unix sockets.
        # x.report('Datadog::Transport::HTTP with Unix socket adapter') do
        #   iterations.times do
        #     unix_transport.send_traces(traces)
        #   end
        # end

        x.report('Datadog::Transport::HTTP with test adapter') do
          iterations.times do
            test_transport.send_traces(traces)
          end
        end
      end
    end
  end
end
