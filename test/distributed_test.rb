require 'helper'
require 'ddtrace/distributed'

class DistributedTest < Minitest::Test
  def test_parse_trace_headers
    test_cases = {
      %w[1 2] => [1, 2],
      [3, 5] => [3, 5],
      %w[9223372036854775807 9223372036854775807] => [9223372036854775807, 9223372036854775807], # 2**63 - 1
      %w[9223372036854775808 9223372036854775808] => [nil, nil], # 2**63
      %w[18446744073709551615 18446744073709551615] => [nil, nil], # 2**64 - 1
      %w[18446744073709551616 18446744073709551616] => [nil, nil], # 2**64
      %w[1000000000000000000000 1000000000000000000000] => [nil, nil],
      %w[abc def] => [nil, nil],
      [-1 - 2] => [nil, nil],
      %w[-1 -2] => [nil, nil],
      [3, 'ooops'] => [nil, nil],
      ['ooops', 5] => [nil, nil],
      [3, nil] => [nil, nil],
      [nil, 5] => [nil, nil],
      [nil, nil] => [nil, nil]
    }
    test_cases.each do |k, v|
      trace_id, parent_id = Datadog::Distributed.parse_trace_headers(k[0], k[1])
      w = [trace_id, parent_id]
      if v[0].nil?
        assert_nil(trace_id, "unexpected trace_id (#{k} should return #{v} but got #{w})")
      else
        assert_equal(v[0], trace_id, "trace_id should match (#{k} should return #{v} but got #{w})")
      end
      if v[1].nil?
        assert_nil(parent_id, "unexpected parent_id (#{k} should return #{v} but got #{w})")
      else
        assert_equal(v[1], parent_id, "parent_id should match (#{k} should return #{v} but got #{w})")
      end
    end
  end
end
