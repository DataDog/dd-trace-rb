require 'spec_helper'

require 'benchmark'
require 'ddtrace'
require 'ddtrace/transport/http'

RSpec.describe 'Transport::HTTP benchmarks' do
  let(:iterations) { 100 }

  before(:each) { skip('Performance test does not run in CI.') }

  describe '#send' do
    let!(:http_transport) { Datadog::HTTPTransport.new }
    let!(:transport_http) { Datadog::Transport::HTTP.default }

    it do
      Benchmark.bm do |x|
        x.report('Datadog::HTTPTransport') do
          iterations.times do
            traces = get_test_traces(2)
            http_transport.send(:traces, traces)
          end
        end

        x.report('Datadog::Transport::HTTP') do
          iterations.times do
            traces = get_test_traces(2)
            transport_http.send_traces(traces)
          end
        end
      end
    end
  end
end
