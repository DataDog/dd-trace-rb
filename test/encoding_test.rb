require 'helper'
require 'ddtrace/span'
require 'ddtrace/encoding'

class TracerTest < Minitest::Test
  def test_traces_encoding_json
    # test encoding for JSON format
    encoder = Datadog::Encoding::JSONEncoder.new()
    traces = get_test_traces(2)
    to_send = encoder.encode_traces(traces)

    assert to_send.is_a? String
    # the spans list must be a list of traces
    items = JSON.parse(to_send)
    assert_equal(items.length, 2)
    assert_equal(items[0].length, 2)
    assert_equal(items[1].length, 2)
    # each span must be properly formatted
    span = items[0][0]
    assert span['span_id']
    assert span['parent_id']
    assert span['trace_id']
    assert span['name']
    assert span['service']
    assert span['resource']
    assert span['type']
    assert span['meta']
    assert span['error']
    assert span['start']
    assert span['duration']
  end
end
