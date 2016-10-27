require 'helper'
require 'ddtrace/span'
require 'ddtrace/encoding'

class TracerTest < Minitest::Test
  def test_traces_encoding
    # test encoding for JSON format
    traces = []
    defaults = {
      service: 'test-app',
      resource: '/traces',
      span_type: 'web',
    }
    traces << [
        Datadog::Span.new(nil, 'client.testing', **defaults).finish(),
        Datadog::Span.new(nil, 'client.testing', **defaults).finish()
    ]
    traces << [
        Datadog::Span.new(nil, 'client.testing', **defaults).finish(),
        Datadog::Span.new(nil, 'client.testing', **defaults).finish()
    ]

    to_send = Datadog::Encoding.encode_spans(traces)

    assert to_send.is_a? String
    # the spans list must be flatten
    items = JSON.load(to_send)
    assert_equal(items.length, 4)
    # each span must be properly formatted
    span = items[0]
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
