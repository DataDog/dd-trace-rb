require 'helper'
require 'contrib/rails/test_helper'

class DatabaseTracingTest < ActiveSupport::TestCase
  test 'active record is properly traced' do
    # use a dummy tracer
    tracer = get_test_tracer
    Rails.configuration.datadog_trace[:tracer] = tracer

    # make the query and assert the proper spans
    Article.count
    spans = tracer.writer.spans()
    assert_equal(spans.length, 1)

    span = spans[-1]
    assert_equal(span.name, 'sqlite.query')
    assert_equal(span.span_type, 'sql')
    assert_equal(span.get_tag('rails.db.vendor'), 'sqlite')
    assert_equal(span.get_tag('sql.query'), 'SELECT COUNT(*) FROM "articles"')
    assert span.to_hash[:duration] > 0
  end
end
