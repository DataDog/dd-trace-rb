require('helper')
require('ddtrace/tracer')
require('ddtrace/span')
require('ddtrace/propagation/distributed_headers')
require('spec_helper')
RSpec.describe Datadog::DistributedHeaders do
  it('valid without sampling priority') do
    test_cases = {
      { 'HTTP_X_DATADOG_TRACE_ID' => '123', 'HTTP_X_DATADOG_PARENT_ID' => '456' } => true,
      { :HTTP_X_DATADOG_TRACE_ID => '123',
        'HTTP_X_DATADOG_PARENT_ID' => '456',
        'HTTP_X_DATADOG_SAMPLING_PRIORITY' => '0' } => true,
      { 'HTTP_X_DATADOG_TRACE_ID' => '123',
        'HTTP_X_DATADOG_PARENT_ID' => '456',
        'HTTP_X_DATADOG_SAMPLING_PRIORITY' => '1' } => true,
      { 'HTTP_X_DATADOG_TRACE_ID' => '123',
        'HTTP_X_DATADOG_PARENT_ID' => '456',
        'HTTP_X_DATADOG_SAMPLING_PRIORITY' => '999' } => true,
      { 'HTTP_X_DATADOG_TRACE_ID' => 'a', 'HTTP_X_DATADOG_PARENT_ID' => '456',
        'HTTP_X_DATADOG_SAMPLING_PRIORITY' => '0' } => false,
      { 'HTTP_X_DATADOG_TRACE_ID' => '123',
        'HTTP_X_DATADOG_PARENT_ID' => 'b',
        'HTTP_X_DATADOG_SAMPLING_PRIORITY' => '0' } => false,
      { 'HTTP_X_DATADOG_TRACE_ID' => '123',
        'HTTP_X_DATADOG_PARENT_ID' => '456',
        'HTTP_X_DATADOG_SAMPLING_PRIORITY' => 'ooops' } => true,
      { 'HTTP_X_DATADOG_TRACE_ID' => '0',
        'HTTP_X_DATADOG_PARENT_ID' => '0' } => false,
      { 'HTTP_X_DATADOG_TRACE_TYPO' => '123',
        'HTTP_X_DATADOG_PARENT_ID' => '456' } => false,
      { 'HTTP_X_DATADOG_TRACE_ID' => '123',
        'HTTP_X_DATADOG_PARENT_TYPO' => '456' } => false
    }
    test_cases.each do |env, expected|
      dh = Datadog::DistributedHeaders.new(env)
      if dh.valid?
        expect(true).to(eq(expected))
      else
        expect(false).to(eq(expected))
      end
    end
  end
  it('trace id') do
    test_cases = {
      { 'HTTP_X_DATADOG_TRACE_ID' => '123' } => 123,
      { 'HTTP_X_DATADOG_TRACE_ID' => '0' } => nil,
      { 'HTTP_X_DATADOG_TRACE_ID' => '-1' } => nil,
      { 'HTTP_X_DATADOG_TRACE_ID' => 'ooops' } => nil,
      { 'HTTP_X_DATADOG_TRACE_TYPO' => '1' } => nil,
      { 'HTTP_X_DATADOG_TRACE_ID' => Datadog::Span::MAX_ID.to_s } => nil,
      { 'HTTP_X_DATADOG_TRACE_ID' => (Datadog::Span::MAX_ID - 1).to_s } => (Datadog::Span::MAX_ID - 1)
    }
    test_cases.each do |env, expected|
      dh = Datadog::DistributedHeaders.new(env)
      if expected
        expect(dh.trace_id).to(eq(expected))
      else
        expect(dh.trace_id).to(be_nil)
      end
    end
  end
  it('parent id') do
    test_cases = {
      { 'HTTP_X_DATADOG_PARENT_ID' => '123' } => 123,
      { 'HTTP_X_DATADOG_PARENT_ID' => '0' } => nil,
      { 'HTTP_X_DATADOG_PARENT_ID' => '-1' } => nil,
      { 'HTTP_X_DATADOG_PARENT_ID' => 'ooops' } => nil,
      { 'HTTP_X_DATADOG_PARENT_TYPO' => '1' } => nil,
      { 'HTTP_X_DATADOG_PARENT_ID' => Datadog::Span::MAX_ID.to_s } => nil,
      { 'HTTP_X_DATADOG_PARENT_ID' => (Datadog::Span::MAX_ID - 1).to_s } => (Datadog::Span::MAX_ID - 1)
    }
    test_cases.each do |env, expected|
      dh = Datadog::DistributedHeaders.new(env)
      if expected
        expect(dh.parent_id).to(eq(expected))
      else
        expect(dh.parent_id).to(be_nil)
      end
    end
  end
  it('sampling priority') do
    test_cases = {
      { 'HTTP_X_DATADOG_SAMPLING_PRIORITY' => '0' } => 0,
      { 'HTTP_X_DATADOG_SAMPLING_PRIORITY' => '1' } => 1,
      { 'HTTP_X_DATADOG_SAMPLING_PRIORITY' => '2' } => 2,
      { 'HTTP_X_DATADOG_SAMPLING_PRIORITY' => '999' } => 999,
      { 'HTTP_X_DATADOG_SAMPLING_PRIORITY' => '-1' } => nil,
      { 'HTTP_X_DATADOG_SAMPLING_PRIORITY' => 'ooops' } => 0,
      {} => nil,
      { 'HTTP_X_DATADOG_SAMPLING_TYPO' => '1' } => nil
    }
    test_cases.each do |env, expected|
      dh = Datadog::DistributedHeaders.new(env)
      if expected
        expect(dh.sampling_priority).to(eq(expected))
      else
        expect(dh.sampling_priority).to(be_nil)
      end
    end
  end
end
