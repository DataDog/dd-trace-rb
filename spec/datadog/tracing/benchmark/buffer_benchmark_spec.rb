require 'spec_helper'

require_relative 'support/benchmark_helper'

RSpec.describe 'Microbenchmark Buffer' do
  let(:max_size) { Datadog::Workers::AsyncTransport::DEFAULT_BUFFER_MAX_SIZE }
  let(:span) { get_test_traces(1).flatten }

  let(:steps) { [max_size / 100, max_size / 10, max_size, max_size * 2] } # Number of elements pushed to buffer

  def subject(pushes)
    i = 0
    while i < pushes
      buffer.push(span)
      i += 1
    end

    buffer.pop
  end

  describe 'CRubyTraceBuffer' do
    before { skip unless PlatformHelpers.mri? }

    let(:buffer) { Datadog::CRubyTraceBuffer.new(max_size) }

    include_examples 'benchmark'
  end

  describe 'ThreadSafeTraceBuffer' do
    let(:buffer) { Datadog::ThreadSafeTraceBuffer.new(max_size) }

    include_examples 'benchmark'
  end
end
