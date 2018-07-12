require('helper')
require('contrib/rails/test_helper')
require('rails_helper')
RSpec.describe 'Rack middleware spec' do
  before do
    @rails_tracer = Datadog.configuration[:rails][:tracer]
    @rack_tracer = Rails.application.app.instance_variable_get(:@tracer)
    @tracer = get_test_tracer
    Datadog.registry[:rails].reset_options!
    Datadog.configuration[:rails][:tracer] = @tracer
    Datadog.configuration[:rails][:database_service] = get_adapter_name
    Datadog::Contrib::Rails::Framework.setup
  end
  after do
    Datadog.configuration[:rails][:tracer] = @rails_tracer
    Rails.application.app.instance_variable_set(:@tracer, @rack_tracer)
  end
  it('a full request is properly traced') do
    get('/full')
    assert_response(:success)
    spans = @tracer.writer.spans
    if Datadog::Contrib::ActiveRecord::Events::Instantiation.supported?
      expect(6).to(eq(spans.length))
      instantiation_span, database_span, request_span, controller_span, cache_span, render_span = spans
    else
      expect(5).to(eq(spans.length))
      database_span, request_span, controller_span, cache_span, render_span = spans
    end
    expect('rack.request').to(eq(request_span.name))
    expect('http').to(eq(request_span.span_type))
    expect('TracingController#full').to(eq(request_span.resource))
    expect('/full').to(eq(request_span.get_tag('http.url')))
    expect('GET').to(eq(request_span.get_tag('http.method')))
    expect('200').to(eq(request_span.get_tag('http.status_code')))
    expect('rails.action_controller').to(eq(controller_span.name))
    expect('http').to(eq(controller_span.span_type))
    expect('TracingController#full').to(eq(controller_span.resource))
    expect('full').to(eq(controller_span.get_tag('rails.route.action')))
    expect('TracingController').to(eq(controller_span.get_tag('rails.route.controller')))
    expect('rails.render_template').to(eq(render_span.name))
    expect('template').to(eq(render_span.span_type))
    expect('rails.render_template').to(eq(render_span.resource))
    expect('tracing/full.html.erb').to(eq(render_span.get_tag('rails.template_name')))
    adapter_name = get_adapter_name
    expect("#{adapter_name}.query").to(eq(database_span.name))
    expect('sql').to(eq(database_span.span_type))
    expect(adapter_name).to(eq(database_span.service))
    expect(database_span.get_tag('active_record.db.vendor')).to(eq(adapter_name))
    expect(database_span.get_tag('active_record.db.cached')).to(be_nil)
    assert_includes(database_span.resource, 'SELECT')
    assert_includes(database_span.resource, 'FROM')
    assert_includes(database_span.resource, 'articles')
    if Datadog::Contrib::ActiveRecord::Events::Instantiation.supported?
      expect('active_record.instantiation').to(eq(instantiation_span.name))
      expect('custom').to(eq(instantiation_span.span_type))
      expect(Datadog.configuration[:rails][:service_name]).to(eq(instantiation_span.service))
      expect('Article').to(eq(instantiation_span.resource))
      expect('Article').to(eq(instantiation_span.get_tag('active_record.instantiation.class_name')))
      expect('0').to(eq(instantiation_span.get_tag('active_record.instantiation.record_count')))
    end
    expect('rails.cache').to(eq(cache_span.name))
    expect('cache').to(eq(cache_span.span_type))
    expect('SET').to(eq(cache_span.resource))
    expect("#{app_name}-cache").to(eq(cache_span.service))
    expect('file_store').to(eq(cache_span.get_tag('rails.cache.backend').to_s))
    expect('empty-key').to(eq(cache_span.get_tag('rails.cache.key')))
  end
  it('the rack.request span has the Rails exception') do
    get('/error')
    assert_response(:error)
    spans = @tracer.writer.spans
    assert_operator(spans.length, :>=, 2, 'there should be at least 2 spans')
    request_span, controller_span = spans
    expect('rails.action_controller').to(eq(controller_span.name))
    expect(1).to(eq(controller_span.status))
    expect('ZeroDivisionError').to(eq(controller_span.get_tag('error.type')))
    expect('divided by 0').to(eq(controller_span.get_tag('error.msg')))
    refute_nil(controller_span.get_tag('error.stack'))
    expect(request_span.name).to(eq('rack.request'))
    expect('http').to(eq(request_span.span_type))
    expect('TracingController#error').to(eq(request_span.resource))
    expect('/error').to(eq(request_span.get_tag('http.url')))
    expect('GET').to(eq(request_span.get_tag('http.method')))
    expect('500').to(eq(request_span.get_tag('http.status_code')))
    expect(1).to(eq(request_span.status))
    refute_nil(request_span.get_tag('error.stack'))
    expect(request_span.get_tag('error.stack')).to(match(/controllers\.rb.*error/))
    expect(request_span.get_tag('error.stack')).to(match(/\n/))
  end
  it('the rack.request span has the Rails exception, soft error version') do
    get('/soft_error')
    spans = @tracer.writer.spans
    assert_operator(spans.length, :>=, 2, 'there should be at least 2 spans')
    request_span, controller_span = spans
    expect('rails.action_controller').to(eq(controller_span.name))
    expect(1).to(eq(controller_span.status))
    expect(controller_span.get_tag('error.type')).to(be_nil)
    expect(controller_span.get_tag('error.msg')).to(be_nil)
    expect(controller_span.get_tag('error.stack')).to(be_nil)
    expect(request_span.name).to(eq('rack.request'))
    expect('http').to(eq(request_span.span_type))
    expect('TracingController#soft_error').to(eq(request_span.resource))
    expect('/soft_error').to(eq(request_span.get_tag('http.url')))
    expect('GET').to(eq(request_span.get_tag('http.method')))
    expect('520').to(eq(request_span.get_tag('http.status_code')))
    expect(1).to(eq(request_span.status))
    expect(request_span.get_tag('error.stack')).to(be_nil)
  end
  it('the rack.request span has the Rails exception and call stack is correct') do
    get('/sub_error')
    assert_response(:error)
    spans = @tracer.writer.spans
    assert_operator(spans.length, :>=, 2, 'there should be at least 2 spans')
    request_span, controller_span = spans
    expect('rails.action_controller').to(eq(controller_span.name))
    expect(1).to(eq(controller_span.status))
    expect('ZeroDivisionError').to(eq(controller_span.get_tag('error.type')))
    expect('divided by 0').to(eq(controller_span.get_tag('error.msg')))
    refute_nil(controller_span.get_tag('error.stack'))
    expect(request_span.name).to(eq('rack.request'))
    expect('http').to(eq(request_span.span_type))
    expect('TracingController#sub_error').to(eq(request_span.resource))
    expect('/sub_error').to(eq(request_span.get_tag('http.url')))
    expect('GET').to(eq(request_span.get_tag('http.method')))
    expect('500').to(eq(request_span.get_tag('http.status_code')))
    expect(1).to(eq(request_span.status))
    expect('ZeroDivisionError').to(eq(controller_span.get_tag('error.type')))
    expect('divided by 0').to(eq(controller_span.get_tag('error.msg')))
    refute_nil(request_span.get_tag('error.stack'))
    expect(request_span.get_tag('error.stack')).to(match(/controllers\.rb.*error/))
    expect(request_span.get_tag('error.stack')).to(match(/controllers\.rb.*another_nested_error_call/))
    expect(request_span.get_tag('error.stack')).to(match(/controllers\.rb.*a_nested_error_call/))
    expect(request_span.get_tag('error.stack')).to(match(/controllers\.rb.*sub_error/))
    expect(request_span.get_tag('error.stack')).to(match(/\n/))
  end
  it('custom error controllers should not override trace resource names') do
    if Rails.version >= '5.0'
      get('/internal_server_error', headers: { 'action_dispatch.exception' => ArgumentError.new })
    else
      get('/internal_server_error', {}, 'action_dispatch.exception' => ArgumentError.new)
    end
    assert_response(:error)
    spans = @tracer.writer.spans
    expect(spans.length).to(eq(2))
    rack_span = spans.first
    controller_span = spans.last
    expect(1).to(eq(rack_span.status))
    expect(controller_span.resource).to_not(eq(rack_span.resource))
    expect(1).to(eq(controller_span.status))
    expect('ErrorsController#internal_server_error').to(eq(controller_span.resource))
  end
  it('the status code is properly set if Rails controller is bypassed') do
    get('/not_existing')
    assert_response(404)
    spans = @tracer.writer.spans
    assert_operator(spans.length, :>=, 1, 'there should be at least 1 span')
    request_span = spans[0]
    expect(request_span.name).to(eq('rack.request'))
    expect('http').to(eq(request_span.span_type))
    expect('GET 404').to(eq(request_span.resource))
    expect('/not_existing').to(eq(request_span.get_tag('http.url')))
    expect('GET').to(eq(request_span.get_tag('http.method')))
    expect('404').to(eq(request_span.get_tag('http.status_code')))
    expect(0).to(eq(request_span.status))
  end
end
