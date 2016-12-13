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
end
