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

  test 'active record traces instantiation' do
    # Only supported in Rails 4.2+
    if Rails.version >= '4.2'
      begin
        Article.create(title: 'Instantiation test')
        @tracer.writer.spans # Clear spans

        # make the query and assert the proper spans
        Article.all.entries
        spans = @tracer.writer.spans
        assert_equal(2, spans.length)

        instantiation_span = spans.first
        assert_equal(instantiation_span.name, 'active_record.instantiation')
        assert_equal(instantiation_span.span_type, 'custom')
        assert_equal(instantiation_span.service, Datadog.configuration[:rails][:service_name])
        assert_equal(instantiation_span.resource, 'Article')
        assert_equal(instantiation_span.get_tag('active_record.instantiation.class_name'), 'Article')
        assert_equal(instantiation_span.get_tag('active_record.instantiation.record_count'), '1')
      ensure
        Article.delete_all
      end
    end
  end

  test 'active record is sets cached tag' do
    # Make sure query caching is enabled...
    Article.cache do
      # Do two queries (second should cache.)
      Article.count
      Article.count

      # Assert correct number of spans
      spans = @tracer.writer.spans
      assert_equal(spans.length, 2)

      # Assert cached flag not present on first query
      assert_nil(spans.first.get_tag('rails.db.cached'))

      # Assert cached flag set correctly on second query
      assert_equal('true', spans.last.get_tag('rails.db.cached'))
    end
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
