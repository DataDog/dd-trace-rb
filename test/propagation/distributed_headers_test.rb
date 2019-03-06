require 'helper'
require 'ddtrace/tracer'
require 'ddtrace/span'
require 'ddtrace/propagation/distributed_headers'

class DistributedHeadersTest < Minitest::Test
  def test_valid_without_sampling_priority # rubocop:disable Metrics/MethodLength
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
        'HTTP_X_DATADOG_PARENT_ID' => '456',
        'HTTP_X_DATADOG_SAMPLING_PRIORITY' => 'ooops' } =>  true, # corner case, 0 is valid for a sampling priority
      { 'HTTP_X_DATADOG_TRACE_ID' => '0',
        'HTTP_X_DATADOG_PARENT_ID' => '0' } => false,
      { 'HTTP_X_DATADOG_TRACE_TYPO' => '123',
        'HTTP_X_DATADOG_PARENT_ID' => '456' } => false,
      { 'HTTP_X_DATADOG_TRACE_ID' => '123',
        'HTTP_X_DATADOG_PARENT_ID' => 'b',
        'HTTP_X_DATADOG_SAMPLING_PRIORITY' => '0' } => false,
      { 'HTTP_X_DATADOG_TRACE_ID' => '123',
        'HTTP_X_DATADOG_PARENT_TYPO' => '456' } => false,
      # Parent id is not required when origin is synthetics
      { 'HTTP_X_DATADOG_TRACE_ID' => '123',
        'HTTP_X_DATADOG_PARENT_ID' => '0',
        'HTTP_X_DATADOG_ORIGIN' => 'not-synthetics' } => false,
      { 'HTTP_X_DATADOG_TRACE_ID' => '123',
        'HTTP_X_DATADOG_PARENT_ID' => '0',
        'HTTP_X_DATADOG_ORIGIN' => 'synthetics' } => true
    }

    test_cases.each do |env, expected|
      dh = Datadog::DistributedHeaders.new(env)
      if dh.valid?
        assert_equal(expected, true, "with #{env} valid? should be true")
      else
        assert_equal(expected, false, "with #{env} valid? should be false")
      end
    end
  end

  def test_trace_id
    test_cases = {
      { 'HTTP_X_DATADOG_TRACE_ID' => '123' } => 123,
      { 'HTTP_X_DATADOG_TRACE_ID' => '0' } => nil,
      { 'HTTP_X_DATADOG_TRACE_ID' => '-1' } => 18446744073709551615,
      { 'HTTP_X_DATADOG_TRACE_ID' => '-8809075535603237910' } => 9637668538106313706,
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
      { 'HTTP_X_DATADOG_PARENT_ID' => 'a' } => nil,
      { 'HTTP_X_DATADOG_PARENT_ID' => '' } => nil,
      { 'HTTP_X_DATADOG_PARENT_ID' => '-1' } => 18446744073709551615,
      { 'HTTP_X_DATADOG_PARENT_ID' => '-8809075535603237910' } => 9637668538106313706,
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
