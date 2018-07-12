require('helper')
require('contrib/rails/test_helper')
RSpec.describe(TracingController) do
  before do
    @original_tracer = Datadog.configuration[:rails][:tracer]
    @tracer = get_test_tracer
    Datadog.configuration[:rails][:tracer] = @tracer
  end
  after { Datadog.configuration[:rails][:tracer] = @original_tracer }
  it('error in the controller must be traced') do
    expect { get(:error) }.to(raise_error(ZeroDivisionError))
    spans = @tracer.writer.spans
    expect(1).to(eq(spans.length))
    span = spans[0]
    expect('rails.action_controller').to(eq(span.name))
    expect(1).to(eq(span.status))
    expect('http').to(eq(span.span_type))
    expect('TracingController#error').to(eq(span.resource))
    expect('error').to(eq(span.get_tag('rails.route.action')))
    expect('TracingController').to(eq(span.get_tag('rails.route.controller')))
    expect('ZeroDivisionError').to(eq(span.get_tag('error.type')))
    expect('divided by 0').to(eq(span.get_tag('error.msg')))
  end
  it('404 should not be traced as errors') do
    expect { get(:not_found) }.to(raise_error(ActionController::RoutingError))
    spans = @tracer.writer.spans
    expect(1).to(eq(spans.length))
    span = spans[0]
    expect('rails.action_controller').to(eq(span.name))
    expect('http').to(eq(span.span_type))
    expect('TracingController#not_found').to(eq(span.resource))
    expect('not_found').to(eq(span.get_tag('rails.route.action')))
    expect('TracingController').to(eq(span.get_tag('rails.route.controller')))
    return if Rails.version < '3.2.22.5'
    expect(0).to(eq(span.status))
    expect(span.get_tag('error.type')).to(be_nil)
    expect(span.get_tag('error.msg')).to(be_nil)
  end
  it('missing rendering should close the template Span') do
    expect { get(:missing_template) }.to(raise_error(::ActionView::MissingTemplate))
    spans = @tracer.writer.spans
    expect(2).to(eq(spans.length))
    span_request, span_template = spans
    expect('rails.action_controller').to(eq(span_request.name))
    expect(1).to(eq(span_request.status))
    expect('http').to(eq(span_request.span_type))
    expect('TracingController#missing_template').to(eq(span_request.resource))
    expect('missing_template').to(eq(span_request.get_tag('rails.route.action')))
    expect('TracingController').to(eq(span_request.get_tag('rails.route.controller')))
    expect('ActionView::MissingTemplate').to(eq(span_request.get_tag('error.type')))
    assert_includes(span_request.get_tag('error.msg'), 'Missing template views/tracing/ouch.not.here')
    expect('rails.render_template').to(eq(span_template.name))
    expect(1).to(eq(span_template.status))
    expect('template').to(eq(span_template.span_type))
    expect('rails.render_template').to(eq(span_template.resource))
    expect(span_template.get_tag('rails.template_name')).to(be_nil)
    expect(span_template.get_tag('rails.layout')).to(be_nil)
    expect('ActionView::MissingTemplate').to(eq(span_template.get_tag('error.type')))
    assert_includes(span_template.get_tag('error.msg'), 'Missing template views/tracing/ouch.not.here')
  end
  it('missing partial rendering should close the template Span') do
    expect { get(:missing_partial) }.to(raise_error(::ActionView::Template::Error))
    error_msg = if Rails.version > '3.2.22.5'
                  'Missing partial tracing/_ouch.html.erb'
                else
                  'Missing partial tracing/ouch.html'
                end
    spans = @tracer.writer.spans
    expect(3).to(eq(spans.length))
    span_request, span_partial, span_template = spans
    expect('rails.action_controller').to(eq(span_request.name))
    expect(1).to(eq(span_request.status))
    expect('http').to(eq(span_request.span_type))
    expect('TracingController#missing_partial').to(eq(span_request.resource))
    expect('missing_partial').to(eq(span_request.get_tag('rails.route.action')))
    expect('TracingController').to(eq(span_request.get_tag('rails.route.controller')))
    expect('ActionView::Template::Error').to(eq(span_request.get_tag('error.type')))
    assert_includes(span_request.get_tag('error.msg'), error_msg)
    expect('rails.render_partial').to(eq(span_partial.name))
    expect(1).to(eq(span_partial.status))
    expect('template').to(eq(span_partial.span_type))
    expect('rails.render_partial').to(eq(span_partial.resource))
    expect(span_partial.get_tag('rails.template_name')).to(be_nil)
    expect(span_partial.get_tag('rails.layout')).to(be_nil)
    expect('ActionView::MissingTemplate').to(eq(span_partial.get_tag('error.type')))
    assert_includes(span_partial.get_tag('error.msg'), error_msg)
    expect('rails.render_template').to(eq(span_template.name))
    expect(1).to(eq(span_template.status))
    expect('template').to(eq(span_template.span_type))
    expect('rails.render_template').to(eq(span_template.resource))
    expect('tracing/missing_partial.html.erb').to(eq(span_template.get_tag('rails.template_name')))
    expect('layouts/application').to(eq(span_template.get_tag('rails.layout')))
    assert_includes(span_template.get_tag('error.msg'), error_msg)
    expect('ActionView::Template::Error').to(eq(span_template.get_tag('error.type')))
  end
  it('error in the template must be traced') do
    expect { get(:error_template) }.to(raise_error(::ActionView::Template::Error))
    spans = @tracer.writer.spans
    expect(2).to(eq(spans.length))
    span_request, span_template = spans
    expect('rails.action_controller').to(eq(span_request.name))
    expect(1).to(eq(span_request.status))
    expect('http').to(eq(span_request.span_type))
    expect('TracingController#error_template').to(eq(span_request.resource))
    expect('error_template').to(eq(span_request.get_tag('rails.route.action')))
    expect('TracingController').to(eq(span_request.get_tag('rails.route.controller')))
    expect('ActionView::Template::Error').to(eq(span_request.get_tag('error.type')))
    expect('divided by 0').to(eq(span_request.get_tag('error.msg')))
    expect('rails.render_template').to(eq(span_template.name))
    expect(1).to(eq(span_template.status))
    expect('template').to(eq(span_template.span_type))
    expect('rails.render_template').to(eq(span_template.resource))
    if Rails.version >= '3.2.22.5'
      expect('tracing/error.html.erb').to(eq(span_template.get_tag('rails.template_name')))
    end
    assert_includes(span_template.get_tag('rails.template_name'), 'tracing/error.html')
    if Rails.version >= '3.2.22.5'
      expect('layouts/application').to(eq(span_template.get_tag('rails.layout')))
    end
    assert_includes(span_template.get_tag('rails.layout'), 'layouts/application')
    expect('ActionView::Template::Error').to(eq(span_template.get_tag('error.type')))
    expect('divided by 0').to(eq(span_template.get_tag('error.msg')))
  end
  it('error in the template partials must be traced') do
    expect { get(:error_partial) }.to(raise_error(::ActionView::Template::Error))
    spans = @tracer.writer.spans
    expect(3).to(eq(spans.length))
    span_request, span_partial, span_template = spans
    expect('rails.action_controller').to(eq(span_request.name))
    expect(1).to(eq(span_request.status))
    expect('http').to(eq(span_request.span_type))
    expect('TracingController#error_partial').to(eq(span_request.resource))
    expect('error_partial').to(eq(span_request.get_tag('rails.route.action')))
    expect('TracingController').to(eq(span_request.get_tag('rails.route.controller')))
    expect('ActionView::Template::Error').to(eq(span_request.get_tag('error.type')))
    expect('divided by 0').to(eq(span_request.get_tag('error.msg')))
    expect('rails.render_partial').to(eq(span_partial.name))
    expect(1).to(eq(span_partial.status))
    expect('template').to(eq(span_partial.span_type))
    expect('rails.render_partial').to(eq(span_partial.resource))
    if Rails.version >= '3.2.22.5'
      expect('tracing/_inner_error.html.erb').to(eq(span_partial.get_tag('rails.template_name')))
    end
    assert_includes(span_partial.get_tag('rails.template_name'), 'tracing/_inner_error.html')
    expect('ActionView::Template::Error').to(eq(span_partial.get_tag('error.type')))
    expect('divided by 0').to(eq(span_partial.get_tag('error.msg')))
    expect('rails.render_template').to(eq(span_template.name))
    expect(1).to(eq(span_template.status))
    expect('template').to(eq(span_template.span_type))
    expect('rails.render_template').to(eq(span_template.resource))
    if Rails.version >= '3.2.22.5'
      expect('tracing/error_partial.html.erb').to(eq(span_template.get_tag('rails.template_name')))
    end
    assert_includes(span_template.get_tag('rails.template_name'), 'tracing/error_partial.html')
    if Rails.version >= '3.2.22.5'
      expect('layouts/application').to(eq(span_template.get_tag('rails.layout')))
    end
    assert_includes(span_template.get_tag('rails.layout'), 'layouts/application')
    expect('ActionView::Template::Error').to(eq(span_template.get_tag('error.type')))
    expect('divided by 0').to(eq(span_template.get_tag('error.msg')))
  end
end
