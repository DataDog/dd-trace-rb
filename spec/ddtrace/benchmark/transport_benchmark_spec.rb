require 'spec_helper'

require_relative 'support/benchmark_helper'

RSpec.describe 'Microbenchmark Transport' do
  context 'with HTTP transport' do
    include_context 'minimal agent'

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
