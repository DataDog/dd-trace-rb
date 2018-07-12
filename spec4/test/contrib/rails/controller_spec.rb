require('helper')
require('contrib/rails/test_helper')
RSpec.describe(TracingController) do
  before do
    @original_tracer = Datadog.configuration[:rails][:tracer]
    @tracer = get_test_tracer
    Datadog.configuration[:rails][:tracer] = @tracer
  end
  after { Datadog.configuration[:rails][:tracer] = @original_tracer }
  it('request is properly traced') do
    get(:index)
    assert_response(:success)
    spans = @tracer.writer.spans
    expect(2).to(eq(spans.length))
    span = spans[0]
    expect('rails.action_controller').to(eq(span.name))
    expect('http').to(eq(span.span_type))
    expect('TracingController#index').to(eq(span.resource))
    expect('index').to(eq(span.get_tag('rails.route.action')))
    expect('TracingController').to(eq(span.get_tag('rails.route.controller')))
  end
  it('template tracing does not break the code') do
    get(:index)
    assert_response(:success)
    expect(response.body).to(eq('Hello from index.html.erb'))
  end
  it('template partial tracing does not break the code') do
    get(:partial)
    assert_response(:success)
    expect(response.body).to(eq('Hello from _body.html.erb partial'))
  end
  it('template rendering is properly traced') do
    get(:index)
    assert_response(:success)
    spans = @tracer.writer.spans
    expect(2).to(eq(spans.length))
    span = spans[1]
    expect('rails.render_template').to(eq(span.name))
    expect('template').to(eq(span.span_type))
    expect('rails.render_template').to(eq(span.resource))
    if Rails.version >= '3.2.22.5'
      expect('tracing/index.html.erb').to(eq(span.get_tag('rails.template_name')))
    end
    assert_includes(span.get_tag('rails.template_name'), 'tracing/index.html')
    if Rails.version >= '3.2.22.5'
      expect('layouts/application').to(eq(span.get_tag('rails.layout')))
    end
    assert_includes(span.get_tag('rails.layout'), 'layouts/application')
  end
  it('template partial rendering is properly traced') do
    get(:partial)
    assert_response(:success)
    spans = @tracer.writer.spans
    expect(3).to(eq(spans.length))
    _, span_partial, span_template = spans
    expect('rails.render_partial').to(eq(span_partial.name))
    expect('template').to(eq(span_partial.span_type))
    expect('rails.render_partial').to(eq(span_partial.resource))
    if Rails.version >= '3.2.22.5'
      expect('tracing/_body.html.erb').to(eq(span_partial.get_tag('rails.template_name')))
    end
    assert_includes(span_partial.get_tag('rails.template_name'), 'tracing/_body.html')
    expect(span_template).to(eq(span_partial.parent))
  end
  it('template nested partial rendering is properly traced') do
    get(:nested_partial)
    assert_response(:success)
    expect(@tracer.call_context.trace.all?(&:finished?)).to(eq(true))
    spans = @tracer.writer.spans
    expect(4).to(eq(spans.length))
    _, span_outer_partial, span_inner_partial, span_template = spans
    expect(span_outer_partial.name).to(eq('rails.render_partial'))
    expect(span_outer_partial.span_type).to(eq('template'))
    expect(span_outer_partial.resource).to(eq('rails.render_partial'))
    if Rails.version >= '3.2.22.5'
      expect(span_outer_partial.get_tag('rails.template_name')).to(eq('tracing/_outer_partial.html.erb'))
    end
    assert_includes(span_outer_partial.get_tag('rails.template_name'), 'tracing/_outer_partial.html')
    expect(span_outer_partial.parent).to(eq(span_template))
    expect(span_inner_partial.name).to(eq('rails.render_partial'))
    expect(span_inner_partial.span_type).to(eq('template'))
    expect(span_inner_partial.resource).to(eq('rails.render_partial'))
    if Rails.version >= '3.2.22.5'
      expect(span_inner_partial.get_tag('rails.template_name')).to(eq('tracing/_inner_partial.html.erb'))
    end
    assert_includes(span_inner_partial.get_tag('rails.template_name'), 'tracing/_inner_partial.html')
    expect(span_inner_partial.parent).to(eq(span_outer_partial))
  end
  it('a full request with database access on the template') do
    get(:full)
    assert_response(:success)
    spans = @tracer.writer.spans
    if Datadog::Contrib::ActiveRecord::Events::Instantiation.supported?
      expect(5).to(eq(spans.length))
      span_instantiation, span_database, span_request, span_cache, span_template = spans
      adapter_name = get_adapter_name
      expect('active_record.instantiation').to(eq(span_instantiation.name))
      expect('rails.cache').to(eq(span_cache.name))
      expect("#{adapter_name}.query").to(eq(span_database.name))
      expect('rails.render_template').to(eq(span_template.name))
      expect('rails.action_controller').to(eq(span_request.name))
      expect(span_request.parent).to(be_nil)
      expect(span_request).to(eq(span_template.parent))
      expect(span_template).to(eq(span_database.parent))
      expect(span_template).to(eq(span_instantiation.parent))
    else
      expect(4).to(eq(spans.length))
      span_database, span_request, span_cache, span_template = spans
      adapter_name = get_adapter_name
      expect('rails.cache').to(eq(span_cache.name))
      expect("#{adapter_name}.query").to(eq(span_database.name))
      expect('rails.render_template').to(eq(span_template.name))
      expect('rails.action_controller').to(eq(span_request.name))
      expect(span_request.parent).to(be_nil)
      expect(span_request).to(eq(span_template.parent))
      expect(span_template).to(eq(span_database.parent))
    end

    expect(span_request).to(eq(span_cache.parent))
  end
  it('multiple calls should not leave an unfinished span in the local thread buffer') do
    get(:full)
    assert_response(:success)
    expect(Thread.current[:datadog_span]).to(be_nil)
    get(:full)
    assert_response(:success)
    expect(Thread.current[:datadog_span]).to(be_nil)
  end
  it('error should be trapped and reported as such') do
    err = false
    get(:error) rescue err = true
    expect(err).to(eq(true))
    spans = @tracer.writer.spans
    expect(spans.length).to(eq(1))
    span = spans[0]
    expect(span.name).to(eq('rails.action_controller'))
    expect(span.status).to(eq(1))
    expect(span.get_tag('error.type')).to(eq('ZeroDivisionError'))
    expect(span.get_tag('error.msg')).to(eq('divided by 0'))
    expect(span.get_tag('error.stack')).not_to be_nil
  end
  it('not found error should not be reported as an error') do
    err = false
    get(:not_found) rescue err = true
    expect(err).to(eq(true))
    spans = @tracer.writer.spans
    expect(spans.length).to(eq(1))
    span = spans[0]
    expect(span.name).to(eq('rails.action_controller'))
    if Rails.version >= '3.2'
      expect(span.status).to(eq(0))
      expect(span.get_tag('error.type')).to(be_nil)
      expect(span.get_tag('error.msg')).to(be_nil)
      expect(span.get_tag('error.stack')).to(be_nil)
    end
  end
  it('http error code should be trapped and reported as such, even with no exception') do
    get(:soft_error)
    spans = @tracer.writer.spans
    if Rails::VERSION::MAJOR.to_i >= 5
      expect(spans.length).to(eq(1))
    else
      expect(spans.length).to be >= 1
    end
    span = spans[0]
    expect(span.name).to(eq('rails.action_controller'))
    expect(span.status).to(eq(1))
    expect(span.get_tag('error.type')).to(be_nil)
    expect(span.get_tag('error.msg')).to(be_nil)
    expect(span.get_tag('error.stack')).to(be_nil)
  end
  it('custom resource names can be set') do
    get(:custom_resource)
    assert_response(:success)
    spans = @tracer.writer.spans
    expect(1).to(eq(spans.length))
    spans.first.tap { |span| expect(span.resource).to(eq('custom-resource')) }
  end
  it('custom tags can be set') do
    get(:custom_tag)
    assert_response(:success)
    spans = @tracer.writer.spans
    expect(1).to(eq(spans.length))
    spans.first.tap do |span|
      expect(span.get_tag('custom-tag')).to(eq('custom-tag-value'))
    end
  end
  it('combining rails and custom tracing is supported') do
    @tracer.trace('a-parent') do
      get(:index)
      assert_response(:success)
      @tracer.trace('a-brother') {}
    end
    spans = @tracer.writer.spans
    expect(spans.length).to(eq(4))
    brother_span, parent_span, controller_span = spans
    expect(controller_span.name).to(eq('rails.action_controller'))
    expect(controller_span.span_type).to(eq('http'))
    expect(controller_span.resource).to(eq('TracingController#index'))
    expect(controller_span.get_tag('rails.route.action')).to(eq('index'))
    expect(controller_span.get_tag('rails.route.controller')).to(eq('TracingController'))
    expect(parent_span.name).to(eq('a-parent'))
    expect(brother_span.name).to(eq('a-brother'))
    expect(parent_span.trace_id).to(eq(controller_span.trace_id))
    expect(brother_span.trace_id).to(eq(controller_span.trace_id))
    expect(controller_span.parent_id).to(eq(parent_span.span_id))
    expect(controller_span.parent_id).to(eq(brother_span.parent_id))
  end
end
