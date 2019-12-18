require 'helper'

require 'contrib/rails/test_helper'

# rubocop:disable Metrics/ClassLength
class TracingControllerTest < ActionController::TestCase
  setup do
    @original_tracer = Datadog.configuration[:rails][:tracer]
    @tracer = get_test_tracer
    Datadog.configuration[:rails][:tracer] = @tracer
  end

  teardown do
    Datadog.configuration[:rails][:tracer] = @original_tracer
  end

  test 'request is properly traced' do
    # make the request and assert the proper span
    get :index
    assert_response :success
    spans = @tracer.writer.spans()
    assert_equal(spans.length, 2)

    span = spans[0]
    assert_equal(span.name, 'rails.action_controller')
    assert_equal(span.span_type, 'web')
    assert_equal(span.resource, 'TracingController#index')
    assert_equal(span.get_tag('rails.route.action'), 'index')
    assert_equal(span.get_tag('rails.route.controller'), 'TracingController')
  end

  test 'template tracing does not break the code' do
    # render a template and expect the correct result
    get :index
    assert_response :success
    assert_equal('Hello from index.html.erb', response.body)
  end

  test 'template partial tracing does not break the code' do
    # render a partial and expect the correct result
    get :partial
    assert_response :success
    assert_equal('Hello from _body.html.erb partial', response.body)
  end

  test 'template rendering is properly traced' do
    # render the template and assert the proper span
    get :index
    assert_response :success
    spans = @tracer.writer.spans()
    assert_equal(spans.length, 2)
    span = spans[1]
    assert_equal(span.name, 'rails.render_template')
    assert_equal(span.span_type, 'template')
    assert_equal(span.resource, 'tracing/index.html.erb')
    assert_equal(span.get_tag('rails.template_name'), 'tracing/index.html.erb') if Rails.version >= '3.2.22.5'
    assert_includes(span.get_tag('rails.template_name'), 'tracing/index.html')
    assert_equal(span.get_tag('rails.layout'), 'layouts/application') if Rails.version >= '3.2.22.5'
    assert_includes(span.get_tag('rails.layout'), 'layouts/application')
  end

  test 'template rendering is properly without explicit layout' do
    begin
      # Most users of Rails do not explicitly specify a controller layout
      TracingController.class_eval { layout nil }

      # render the template and assert the proper span
      get :index
      assert_response :success
      spans = @tracer.writer.spans()
      assert_equal(spans.length, 2)
      span = spans[1]
      assert_equal(span.name, 'rails.render_template')
      assert_equal(span.span_type, 'template')
      assert_equal(span.resource, 'tracing/index.html.erb') if Rails.version >= '3.2.22.5'
      assert_includes(span.resource, 'tracing/index.html')
      assert_equal(span.get_tag('rails.template_name'), 'tracing/index.html.erb') if Rails.version >= '3.2.22.5'
      assert_includes(span.get_tag('rails.template_name'), 'tracing/index.html')
    ensure
      TracingController.class_eval { layout 'application' }
    end
  end

  test 'template partial rendering is properly traced' do
    # render the template and assert the proper span
    get :partial
    assert_response :success
    spans = @tracer.writer.spans()
    assert_equal(spans.length, 3)

    _, span_partial, span_template = spans
    assert_equal(span_partial.name, 'rails.render_partial')
    assert_equal(span_partial.span_type, 'template')
    assert_equal(span_partial.resource, 'tracing/_body.html.erb')
    assert_equal(span_partial.get_tag('rails.template_name'), 'tracing/_body.html.erb') if Rails.version >= '3.2.22.5'
    assert_includes(span_partial.get_tag('rails.template_name'), 'tracing/_body.html')
    assert_equal(span_partial.parent, span_template)
  end

  test 'template nested partial rendering is properly traced' do
    # render the template and assert the proper span
    get :nested_partial
    assert_response :success

    # Verify all spans have closed
    assert_equal(true, @tracer.call_context.trace.all?(&:finished?))

    # Verify correct number of spans
    spans = @tracer.writer.spans
    assert_equal(spans.length, 4)

    _, span_inner_partial, span_outer_partial, span_template = spans

    # Outer partial
    assert_equal('rails.render_partial', span_outer_partial.name)
    assert_equal('template', span_outer_partial.span_type)
    assert_equal('tracing/_outer_partial.html.erb', span_outer_partial.resource)
    if Rails.version >= '3.2.22.5'
      assert_equal('tracing/_outer_partial.html.erb', span_outer_partial.get_tag('rails.template_name'))
    end
    assert_includes(span_outer_partial.get_tag('rails.template_name'), 'tracing/_outer_partial.html')
    assert_equal(span_template, span_outer_partial.parent)

    # Inner partial
    assert_equal('rails.render_partial', span_inner_partial.name)
    assert_equal('template', span_inner_partial.span_type)
    assert_equal('tracing/_inner_partial.html.erb', span_inner_partial.resource)
    if Rails.version >= '3.2.22.5'
      assert_equal('tracing/_inner_partial.html.erb', span_inner_partial.get_tag('rails.template_name'))
    end
    assert_includes(span_inner_partial.get_tag('rails.template_name'), 'tracing/_inner_partial.html')
    assert_equal(span_outer_partial, span_inner_partial.parent)
  end

  test 'a full request with database access on the template' do
    # render the endpoint
    get :full
    assert_response :success
    spans = @tracer.writer.spans

    # rubocop:disable Style/IdenticalConditionalBranches
    if Datadog::Contrib::ActiveRecord::Events::Instantiation.supported?
      assert_equal(spans.length, 5)
      span_instantiation, span_database, span_request, span_cache, span_template = spans

      # assert the spans
      adapter_name = get_adapter_name
      assert_equal(span_instantiation.name, 'active_record.instantiation')
      assert_equal(span_cache.name, 'rails.cache')
      assert_equal(span_database.name, "#{adapter_name}.query")
      assert_equal(span_template.name, 'rails.render_template')
      assert_equal(span_request.name, 'rails.action_controller')

      # assert the parenting
      assert_nil(span_request.parent)
      assert_equal(span_template.parent, span_request)
      assert_equal(span_database.parent, span_template)
      assert_equal(span_instantiation.parent, span_template)
      assert_equal(span_cache.parent, span_request)
    else
      assert_equal(spans.length, 4)
      span_database, span_request, span_cache, span_template = spans

      # assert the spans
      adapter_name = get_adapter_name
      assert_equal(span_cache.name, 'rails.cache')
      assert_equal(span_database.name, "#{adapter_name}.query")
      assert_equal(span_template.name, 'rails.render_template')
      assert_equal(span_request.name, 'rails.action_controller')

      # assert the parenting
      assert_nil(span_request.parent)
      assert_equal(span_template.parent, span_request)
      assert_equal(span_database.parent, span_template)
      assert_equal(span_cache.parent, span_request)
    end
  end

  test 'multiple calls should not leave an unfinished span in the local thread buffer' do
    get :full
    assert_response :success
    assert_nil(Thread.current[:datadog_span])

    get :full
    assert_response :success
    assert_nil(Thread.current[:datadog_span])
  end

  test 'error should be trapped and reported as such' do
    err = false
    begin
      get :error
    rescue
      err = true
    end
    assert_equal(true, err, 'should have raised an error')
    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)
    span = spans[0]
    assert_equal('rails.action_controller', span.name)
    assert_equal(1, span.status, 'span should be flagged as an error')
    assert_equal('ZeroDivisionError', span.get_tag('error.type'), 'type should contain the class name of the error')
    assert_equal('divided by 0', span.get_tag('error.msg'), 'msg should state we tried to divided by 0')
    refute_nil(span.get_tag('error.stack'))
  end

  test 'not found error should not be reported as an error' do
    err = false
    begin
      get :not_found
    rescue
      err = true
    end
    assert_equal(true, err, 'should have raised an error')
    spans = @tracer.writer.spans
    assert_equal(1, spans.length)
    span = spans[0]
    assert_equal('rails.action_controller', span.name)

    # Rails 3.0 doesn't know how to convert exceptions to 'not found'
    # Expect newer versions to correctly not flag this span.
    if Rails.version >= '3.2'
      assert_equal(0, span.status, 'span should not be flagged as an error')
      assert_nil(span.get_tag('error.type'))
      assert_nil(span.get_tag('error.msg'))
      assert_nil(span.get_tag('error.stack'))
    end
  end

  test 'http error code should be trapped and reported as such, even with no exception' do
    get :soft_error

    spans = @tracer.writer.spans()
    if Rails::VERSION::MAJOR.to_i >= 5
      assert_equal(1, spans.length)
    else
      assert_operator(spans.length, :>=, 1,
                      'legacy code (rails <= 4) uses render with a status, so there coule be an extra render span')
    end
    span = spans[0]
    assert_equal('rails.action_controller', span.name)
    assert_equal(1, span.status, 'span should be flagged as an error')
    assert_nil(span.get_tag('error.type'), 'type should be undefined')
    assert_nil(span.get_tag('error.msg'), 'msg should be empty')
    assert_nil(span.get_tag('error.stack'), 'no error stack')
  end

  test 'custom resource names can be set' do
    get :custom_resource
    assert_response :success
    spans = @tracer.writer.spans
    assert_equal(spans.length, 1)

    spans.first.tap do |span|
      assert_equal('custom-resource', span.resource)
    end
  end

  test 'custom tags can be set' do
    get :custom_tag
    assert_response :success
    spans = @tracer.writer.spans
    assert_equal(spans.length, 1)

    spans.first.tap do |span|
      assert_equal('custom-tag-value', span.get_tag('custom-tag'))
    end
  end

  test 'combining rails and custom tracing is supported' do
    @tracer.trace('a-parent') do
      get :index
      assert_response :success
      @tracer.trace('a-brother') do
      end
    end

    spans = @tracer.writer.spans()
    assert_equal(4, spans.length)

    brother_span, parent_span, controller_span, = spans
    assert_equal('rails.action_controller', controller_span.name)
    assert_equal('web', controller_span.span_type)
    assert_equal('TracingController#index', controller_span.resource)
    assert_equal('index', controller_span.get_tag('rails.route.action'))
    assert_equal('TracingController', controller_span.get_tag('rails.route.controller'))
    assert_equal('a-parent', parent_span.name)
    assert_equal('a-brother', brother_span.name)
    assert_equal(controller_span.trace_id, parent_span.trace_id)
    assert_equal(controller_span.trace_id, brother_span.trace_id)
    assert_equal(parent_span.span_id, controller_span.parent_id)
    assert_equal(brother_span.parent_id, controller_span.parent_id)
  end
end
