require('helper')
require('contrib/rails/test_helper')
RSpec.describe(DatabaseTracing) do
  before do
    @original_tracer = Datadog.configuration[:rails][:tracer]
    @tracer = get_test_tracer
    Datadog.configure do |c|
      c.use(:rails, database_service: get_adapter_name, tracer: @tracer)
    end
    Datadog.configuration[:active_record][:service_name] = get_adapter_name
    Datadog.configuration[:active_record][:tracer] = @tracer
  end
  after do
    Datadog.configuration[:rails][:tracer] = @original_tracer
    Datadog.configuration[:active_record][:tracer] = @original_tracer
  end
  it('active record is properly traced') do
    Article.count
    spans = @tracer.writer.spans
    expect(spans.length).to(eq(1))
    span = spans.first
    adapter_name = get_adapter_name
    database_name = get_database_name
    adapter_host = get_adapter_host
    adapter_port = get_adapter_port
    expect("#{adapter_name}.query").to(eq(span.name))
    expect('sql').to(eq(span.span_type))
    expect(adapter_name).to(eq(span.service))
    expect(adapter_name).to(eq(span.get_tag('active_record.db.vendor')))
    expect(database_name).to(eq(span.get_tag('active_record.db.name')))
    expect(span.get_tag('active_record.db.cached')).to(be_nil)
    expect(span.get_tag('out.host')).to(eq(adapter_host.to_s))
    expect(span.get_tag('out.port')).to(eq(adapter_port.to_s))
    assert_includes(span.resource, 'SELECT COUNT(*) FROM')
    expect(span.get_tag('sql.query')).to(be_nil)
  end
  it('active record traces instantiation') do
    if Datadog::Contrib::ActiveRecord::Events::Instantiation.supported?
      begin
        (Article.create(title: 'Instantiation test')
         @tracer.writer.spans
         Article.all.entries
         spans = @tracer.writer.spans
         expect(spans.length).to(eq(2))
         instantiation_span = spans.first
         expect('active_record.instantiation').to(eq(instantiation_span.name))
         expect('custom').to(eq(instantiation_span.span_type))
         expect('active_record').to(eq(instantiation_span.service))
         expect('Article').to(eq(instantiation_span.resource))
         expect('Article').to(eq(instantiation_span.get_tag('active_record.instantiation.class_name')))
         expect('1').to(eq(instantiation_span.get_tag('active_record.instantiation.record_count'))))
      ensure
        Article.delete_all
      end
    end
  end
  it('active record traces instantiation inside parent trace') do
    if Datadog::Contrib::ActiveRecord::Events::Instantiation.supported?
      begin
        (Article.create(title: 'Instantiation test')
         @tracer.writer.spans
         @tracer.trace('parent.span', service: 'parent-service') do
           Article.all.entries
         end
         spans = @tracer.writer.spans
         expect(spans.length).to(eq(3))
         parent_span = spans.find { |s| (s.name == 'parent.span') }
         instantiation_span = spans.find { |s| (s.name == 'active_record.instantiation') }
         expect('parent-service').to(eq(parent_span.service))
         expect('active_record.instantiation').to(eq(instantiation_span.name))
         expect('custom').to(eq(instantiation_span.span_type))
         expect(parent_span.service).to(eq(instantiation_span.service))
         expect('Article').to(eq(instantiation_span.resource))
         expect('Article').to(eq(instantiation_span.get_tag('active_record.instantiation.class_name')))
         expect('1').to(eq(instantiation_span.get_tag('active_record.instantiation.record_count'))))
      ensure
        Article.delete_all
      end
    end
  end
  it('active record is sets cached tag') do
    Article.cache do
      Article.count
      Article.count
      spans = @tracer.writer.spans
      expect(spans.length).to(eq(2))
      expect(spans.first.get_tag('active_record.db.cached')).to(be_nil)
      expect(spans.last.get_tag('active_record.db.cached')).to(eq('true'))
    end
  end
  it('doing a database call uses the proper service name if it is changed') do
    update_config(:database_service, 'customer-db')
    Article.count
    spans = @tracer.writer.spans
    expect(spans.length).to(eq(1))
    span = spans.first
    expect('customer-db').to(eq(span.service))
    reset_config
  end
end
