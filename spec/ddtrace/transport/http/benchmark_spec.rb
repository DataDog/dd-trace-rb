require 'spec_helper'

require 'benchmark'
require 'ddtrace'
require 'ddtrace/transport/http'

RSpec.describe 'Transport::HTTP benchmarks' do
  let(:iterations) { 1_000 }

  before(:each) { skip('Performance test does not run in CI.') }

  describe 'HTTPTransport#send' do
    subject!(:transport) do
      Datadog::HTTPTransport.new
    end

    it 'HTTPTransport' do
      Benchmark.bm do |x|
        x.report('HTTPTransport') do
          iterations.times do
            traces = get_test_traces(2)
            transport.send(:traces, traces)
          end
        end
      end
    end
  end

  describe 'Transport::HTTP::Client#send' do
    subject!(:transport) do
      Datadog::Transport::HTTP.default
    end

    it 'HTTPTransport' do
      Benchmark.bm do |x|
        x.report('HTTPTransport') do
          iterations.times do
            traces = get_test_traces(2)
            transport.send(:traces, traces)
          end
        end
      end
    end
  end
end
