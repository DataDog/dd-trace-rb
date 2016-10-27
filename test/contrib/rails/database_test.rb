require 'helper'
require 'contrib/rails/test_helper'

class DatabaseTracingTest < ActiveSupport::TestCase
  setup do
    @original_tracer = Rails.configuration.datadog_trace[:tracer]
    @tracer = get_test_tracer
    Rails.configuration.datadog_trace[:tracer] = @tracer
  end

  teardown do
    Rails.configuration.datadog_trace[:tracer] = @original_tracer
  end

  test 'active record is properly traced' do
    # make the query and assert the proper spans
    Article.count
    spans = @tracer.writer.spans()
    assert_equal(spans.length, 1)

    span = spans[-1]
    assert_equal(span.name, 'postgres.query')
    assert_equal(span.span_type, 'sql')
    assert_includes(span.resource, 'SELECT COUNT(*) FROM')
    assert_equal(span.service, 'postgres')
    assert_equal(span.get_tag('rails.db.vendor'), 'postgres')
    assert_includes(span.get_tag('sql.query'), 'SELECT COUNT(*) FROM')
    assert span.to_hash[:duration] > 0
  end

  test 'doing a database call uses the proper service name if it is changed' do
    # update database configuration
    update_config(:default_database_service, 'customer-db')

    # make the query and assert the proper spans
    Article.count
    spans = @tracer.writer.spans()
    assert_equal(spans.length, 1)

    span = spans[-1]
    assert_equal(span.service, 'customer-db')

    # reset the original configuration
    reset_config()
  end
end
