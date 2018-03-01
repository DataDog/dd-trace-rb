require 'contrib/elasticsearch/test_helper'
require 'ddtrace'
require 'helper'
require 'ddtrace/contrib/elasticsearch/quantize'

class ESQuantizeTest < Minitest::Test
  def test_id
    assert_equal('/my/thing/?', Datadog::Contrib::Elasticsearch::Quantize.format_url('/my/thing/1'))
    assert_equal('/my/thing/?/', Datadog::Contrib::Elasticsearch::Quantize.format_url('/my/thing/1/'))
    assert_equal('/my/thing/?/is/cool', Datadog::Contrib::Elasticsearch::Quantize.format_url('/my/thing/1/is/cool'))
    assert_equal('/my/thing/??is=cool', Datadog::Contrib::Elasticsearch::Quantize.format_url('/my/thing/1?is=cool'))
    assert_equal('/my/thing/1two3/z', Datadog::Contrib::Elasticsearch::Quantize.format_url('/my/thing/1two3/z'))
  end

  def test_index
    assert_equal('/my?/thing', Datadog::Contrib::Elasticsearch::Quantize.format_url('/my123456/thing'))
    assert_equal('/my?more/thing', Datadog::Contrib::Elasticsearch::Quantize.format_url('/my123456more/thing'))
    assert_equal('/my?and?/thing', Datadog::Contrib::Elasticsearch::Quantize.format_url('/my123456and789/thing'))
  end

  def test_combine
    assert_equal('/my?/thing/?', Datadog::Contrib::Elasticsearch::Quantize.format_url('/my123/thing/456789'))
  end

  def test_body
    # MGet format
    body = "{\"ids\":[\"1\",\"2\",\"3\"]}"
    quantized_body = "{\"ids\":\"?\"}"
    assert_equal(quantized_body, Datadog::Contrib::Elasticsearch::Quantize.format_body(body))

    # Search format
    body = "{\"query\":{\"match\":{\"title\":\"test\"}}}"
    quantized_body = "{\"query\":{\"match\":{\"title\":\"?\"}}}"
    assert_equal(quantized_body, Datadog::Contrib::Elasticsearch::Quantize.format_body(body))

    # MSearch format
    body = "{}\n{\"query\":{\"match_all\":{}}}\n{\"index\":\"myindex\",\"type\":\"mytype\"}\n{\"query\":{\"query_string\":{\"query\":\"\\\"test\\\"\"}}}\n{\"search_type\":\"count\"}\n{\"aggregations\":{\"published\":{\"terms\":{\"field\":\"published\"}}}}\n"
    quantized_body = "{}\n{\"query\":{\"match_all\":{}}}\n{\"index\":\"?\",\"type\":\"?\"}\n{\"query\":{\"query_string\":{\"query\":\"?\"}}}\n{\"search_type\":\"?\"}\n{\"aggregations\":{\"published\":{\"terms\":{\"field\":\"?\"}}}}"
    assert_equal(quantized_body, Datadog::Contrib::Elasticsearch::Quantize.format_body(body))

    # Bulk format
    body = "{\"index\":{\"_index\":\"myindex\",\"_type\":\"mytype\",\"_id\":1}}\n{\"title\":\"foo\"}\n{\"index\":{\"_index\":\"myindex\",\"_type\":\"mytype\",\"_id\":2}}\n{\"title\":\"foo\"}\n"
    quantized_body = "{\"index\":{\"_index\":\"myindex\",\"_type\":\"mytype\",\"_id\":1}}\n{\"title\":\"?\"}\n{\"index\":{\"_index\":\"myindex\",\"_type\":\"mytype\",\"_id\":2}}\n{\"title\":\"?\"}"
    assert_equal(quantized_body, Datadog::Contrib::Elasticsearch::Quantize.format_body(body))
  end
end
