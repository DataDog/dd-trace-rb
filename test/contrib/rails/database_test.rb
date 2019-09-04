require 'helper'
require 'contrib/rails/test_helper'

class DatabaseTracingTest < ActiveSupport::TestCase
  setup do
    @original_tracer = Datadog.configuration[:rails][:tracer]
    @tracer = get_test_tracer

    Datadog.configure do |c|
      c.use :rails, database_service: get_adapter_name, tracer: @tracer
    end
  end

  teardown do
    Datadog.configuration[:rails][:tracer] = @original_tracer
  end

  test 'active record is properly traced' do
    # make the query and assert the proper spans
    Article.count
    spans = @tracer.writer.spans
    assert_equal(1, spans.length)

    span = spans.first
    adapter_name = get_adapter_name
    database_name = get_database_name
    adapter_host = get_adapter_host
    adapter_port = get_adapter_port
    assert_equal(span.name, "#{adapter_name}.query")
    assert_equal(span.span_type, 'sql')
    assert_equal(span.service, adapter_name)
    assert_equal(span.get_tag('active_record.db.vendor'), adapter_name)
    assert_equal(span.get_tag('active_record.db.name'), database_name)
    assert_nil(span.get_tag('active_record.db.cached'))
    assert_equal(adapter_host.to_s, span.get_tag('out.host'))
    assert_equal(adapter_port.to_s, span.get_tag('out.port'))
    assert_includes(span.resource, 'SELECT COUNT(*) FROM')
    # ensure that the sql.query tag is not set
    assert_nil(span.get_tag('sql.query'))
  end

  test 'active record traces instantiation' do
    if Datadog::Contrib::ActiveRecord::Events::Instantiation.supported?
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
        # Because no parent, and doesn't belong to database service
        assert_equal(instantiation_span.service, 'active_record')
        assert_equal(instantiation_span.resource, 'Article')
        assert_equal(instantiation_span.get_tag('active_record.instantiation.class_name'), 'Article')
        assert_equal(instantiation_span.get_tag('active_record.instantiation.record_count'), '1')
      ensure
        Article.delete_all
      end
    end
  end

  test 'active record traces instantiation inside parent trace' do
    if Datadog::Contrib::ActiveRecord::Events::Instantiation.supported?
      begin
        Article.create(title: 'Instantiation test')
        @tracer.writer.spans # Clear spans

        # make the query and assert the proper spans
        @tracer.trace('parent.span', service: 'parent-service') do
          Article.all.entries
        end
        spans = @tracer.writer.spans
        assert_equal(3, spans.length)
        parent_span = spans.find { |s| s.name == 'parent.span' }
        instantiation_span = spans.find { |s| s.name == 'active_record.instantiation' }

        assert_equal(parent_span.service, 'parent-service')

        assert_equal(instantiation_span.name, 'active_record.instantiation')
        assert_equal(instantiation_span.span_type, 'custom')
        assert_equal(instantiation_span.service, parent_span.service) # Because within parent
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
      assert_equal(2, spans.length)

      # Assert cached flag not present on first query
      assert_nil(spans.first.get_tag('active_record.db.cached'))

      # Assert cached flag set correctly on second query
      assert_equal('true', spans.last.get_tag('active_record.db.cached'))
    end
  end

  test 'doing a database call uses the proper service name if it is changed' do
    # update database configuration
    update_config(:database_service, 'customer-db')

    # make the query and assert the proper spans
    Article.count
    spans = @tracer.writer.spans
    assert_equal(1, spans.length)

    span = spans.first
    assert_equal(span.service, 'customer-db')

    # reset the original configuration
    reset_config
  end
end
