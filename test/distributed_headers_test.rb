require 'helper'
require 'ddtrace/tracer'
require 'ddtrace/span'
require 'ddtrace/distributed_headers'

class DistributedHeadersTest < Minitest::Test
  def test_valid_without_sampling_priority
    test_cases = {
      { 'HTTP_X_DATADOG_TRACE_ID' => '123',
        'HTTP_X_DATADOG_PARENT_ID' => '456' } => true,
      { 'HTTP_X_DATADOG_TRACE_ID' => '123',
        'HTTP_X_DATADOG_PARENT_ID' => '456',
        'HTTP_X_DATADOG_SAMPLING_PRIORITY' => '0' } => true,
      { 'HTTP_X_DATADOG_TRACE_ID' => '123',
        'HTTP_X_DATADOG_PARENT_ID' => '456',
        'HTTP_X_DATADOG_SAMPLING_PRIORITY' => '1' } => true,
      { 'HTTP_X_DATADOG_TRACE_ID' => '123',
        'HTTP_X_DATADOG_PARENT_ID' => '456',
        'HTTP_X_DATADOG_SAMPLING_PRIORITY' => '999' } => true,
      { 'HTTP_X_DATADOG_TRACE_ID' => 'a',
        'HTTP_X_DATADOG_PARENT_ID' => '456',
        'HTTP_X_DATADOG_SAMPLING_PRIORITY' => '0' } => false,
      { 'HTTP_X_DATADOG_TRACE_ID' => '123',
        'HTTP_X_DATADOG_PARENT_ID' => 'b',
        'HTTP_X_DATADOG_SAMPLING_PRIORITY' => '0' } => false,
      { 'HTTP_X_DATADOG_TRACE_ID' => '123',
        'HTTP_X_DATADOG_PARENT_ID' => '456',
        'HTTP_X_DATADOG_SAMPLING_PRIORITY' => 'ooops' } =>  true, # corner case, 0 is valid for a sampling priority
      { 'HTTP_X_DATADOG_TRACE_ID' => '0',
        'HTTP_X_DATADOG_PARENT_ID' => '0' } => false,
      { 'HTTP_X_DATADOG_TRACE_TYPO' => '123',
        'HTTP_X_DATADOG_PARENT_ID' => '456' } => false,
      { 'HTTP_X_DATADOG_TRACE_ID' => '123',
        'HTTP_X_DATADOG_PARENT_TYPO' => '456' } => false
    }

    test_cases.each do |env, expected|
      dh = Datadog::DistributedHeaders.new(env)
      # rubocop:disable Style/DoubleNegation
      assert_equal(expected, !!dh.valid?, "with #{env} valid? should return #{expected}")
    end
  end

  def test_trace_id
    test_cases = {
      { 'HTTP_X_DATADOG_TRACE_ID' => '123' } => 123,
      { 'HTTP_X_DATADOG_TRACE_ID' => '0' } => nil,
      { 'HTTP_X_DATADOG_TRACE_ID' => '-1' } => nil,
      { 'HTTP_X_DATADOG_TRACE_ID' => 'ooops' } => nil,
      { 'HTTP_X_DATADOG_TRACE_TYPO' => '1' } => nil,
      { 'HTTP_X_DATADOG_TRACE_ID' => Datadog::Span::MAX_ID.to_s } => nil,
      { 'HTTP_X_DATADOG_TRACE_ID' => (Datadog::Span::MAX_ID - 1).to_s } => Datadog::Span::MAX_ID - 1
    }

    test_cases.each do |env, expected|
      dh = Datadog::DistributedHeaders.new(env)
      if expected
        assert_equal(expected, dh.trace_id, "with #{env} trace_id should return #{expected}")
      else
        assert_nil(dh.trace_id, "with #{env} trace_id should return nil")
      end
    end
  end

  def test_parent_id
    test_cases = {
      { 'HTTP_X_DATADOG_PARENT_ID' => '123' } => 123,
      { 'HTTP_X_DATADOG_PARENT_ID' => '0' } => nil,
      { 'HTTP_X_DATADOG_PARENT_ID' => '-1' } => nil,
      { 'HTTP_X_DATADOG_PARENT_ID' => 'ooops' } => nil,
      { 'HTTP_X_DATADOG_PARENT_TYPO' => '1' } => nil,
      { 'HTTP_X_DATADOG_PARENT_ID' => Datadog::Span::MAX_ID.to_s } => nil,
      { 'HTTP_X_DATADOG_PARENT_ID' => (Datadog::Span::MAX_ID - 1).to_s } => Datadog::Span::MAX_ID - 1
    }

    test_cases.each do |env, expected|
      dh = Datadog::DistributedHeaders.new(env)
      if expected
        assert_equal(expected, dh.parent_id, "with #{env} parent_id should return #{expected}")
      else
        assert_nil(dh.parent_id, "with #{env} parent_id should return nil")
      end
    end
  end

  def test_sampling_priority
    test_cases = {
      { 'HTTP_X_DATADOG_SAMPLING_PRIORITY' => '0' } => 0,
      { 'HTTP_X_DATADOG_SAMPLING_PRIORITY' => '1' } => 1,
      { 'HTTP_X_DATADOG_SAMPLING_PRIORITY' => '2' } => 2,
      { 'HTTP_X_DATADOG_SAMPLING_PRIORITY' => '999' } => 999,
      { 'HTTP_X_DATADOG_SAMPLING_PRIORITY' => '-1' } => nil,
      { 'HTTP_X_DATADOG_SAMPLING_PRIORITY' => 'ooops' } => 0,
      # nil cases below are very important to test, they are valid real-world use cases
      {} => nil,
      { 'HTTP_X_DATADOG_SAMPLING_TYPO' => '1' } => nil
    }

    test_cases.each do |env, expected|
      dh = Datadog::DistributedHeaders.new(env)
      if expected
        assert_equal(expected, dh.sampling_priority, "with #{env} sampling_priority should return #{expected}")
      else
        assert_nil(dh.sampling_priority, "with #{env} sampling_priority should return nil")
      end
    end
  end
end
