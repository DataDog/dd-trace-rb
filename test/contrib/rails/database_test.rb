require 'helper'
require 'contrib/rails/test_helper'

class DatabaseTracingTest < ActiveSupport::TestCase
  setup do
    @original_tracer = Datadog.configuration[:rails][:tracer]
    @tracer = get_test_tracer
    Datadog.configuration[:rails][:database_service] = get_adapter_name
    Datadog.configuration[:rails][:tracer] = @tracer
  end

  teardown do
    Datadog.configuration[:rails][:tracer] = @original_tracer
  end

  test 'active record is properly traced' do
    # make the query and assert the proper spans
    Article.count
    spans = @tracer.writer.spans
    assert_equal(spans.length, 1)

    span = spans.first
    adapter_name = get_adapter_name
    database_name = get_database_name
    adapter_host = get_adapter_host
    adapter_port = get_adapter_port
    assert_equal(span.name, "#{adapter_name}.query")
    assert_equal(span.span_type, 'sql')
    assert_equal(span.service, adapter_name)
    assert_equal(span.get_tag('rails.db.vendor'), adapter_name)
    assert_equal(span.get_tag('rails.db.name'), database_name)
    assert_nil(span.get_tag('rails.db.cached'))
    assert_equal(adapter_host.to_s, span.get_tag('out.host'))
    assert_equal(adapter_port.to_s, span.get_tag('out.port'))
    assert_includes(span.resource, 'SELECT COUNT(*) FROM')
    # ensure that the sql.query tag is not set
    assert_nil(span.get_tag('sql.query'))
  end

  test 'doing a database call uses the proper service name if it is changed' do
    # update database configuration
    update_config(:database_service, 'customer-db')

    # make the query and assert the proper spans
    Article.count
    spans = @tracer.writer.spans()
    assert_equal(spans.length, 1)

    span = spans.first
    assert_equal(span.service, 'customer-db')

    # reset the original configuration
    reset_config
  end
end
