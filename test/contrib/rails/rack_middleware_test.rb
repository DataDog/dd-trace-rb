require 'helper'

require 'contrib/rails/test_helper'

# rubocop:disable Metrics/ClassLength
class FullStackTest < ActionDispatch::IntegrationTest
  setup do
    # store original tracers
    @rails_tracer = Datadog.configuration[:rails][:tracer]
    @rack_tracer = Rails.application.app.instance_variable_get :@tracer

    # replace the Rails and the Rack tracer with a dummy one;
    # this prevents the overhead to reinitialize the Rails application
    # and the Rack stack
    @tracer = get_test_tracer
    Datadog.configuration[:rails].reset!
    Datadog.configuration[:rails][:tracer] = @tracer
    Datadog.configuration[:rails][:database_service] = get_adapter_name
    Datadog::Contrib::Rails::Framework.setup
  end

  teardown do
    # restore original tracers
    Datadog.configuration[:rails][:tracer] = @rails_tracer
    Rails.application.app.instance_variable_set(:@tracer, @rack_tracer)
  end
  test 'a full request is properly traced' do
    # make the request and assert the proper span
    get '/full'
    assert_response :success

    # get spans
    spans = @tracer.writer.spans

    # spans are sorted alphabetically, and ... controller names start
    # either by m or p (MySQL or PostGreSQL) so the database span is always
    # the first one. Would fail with an adapter named z-something.
    if Datadog::Contrib::ActiveRecord::Events::Instantiation.supported?
      assert_equal(spans.length, 6)
      instantiation_span, database_span, request_span, controller_span, cache_span, render_span = spans
    else
      assert_equal(spans.length, 5)
      database_span, request_span, controller_span, cache_span, render_span = spans
    end

    assert_equal(request_span.name, 'rack.request')
    assert_equal(request_span.span_type, 'web')
    assert_equal(request_span.resource, 'TracingController#full')
    assert_equal(request_span.get_tag('http.url'), '/full')
    assert_equal(request_span.get_tag('http.method'), 'GET')
    assert_equal(request_span.get_tag('http.status_code'), 200)

    assert_equal(controller_span.name, 'rails.action_controller')
    assert_equal(controller_span.span_type, 'web')
    assert_equal(controller_span.resource, 'TracingController#full')
    assert_equal(controller_span.get_tag('rails.route.action'), 'full')
    assert_equal(controller_span.get_tag('rails.route.controller'), 'TracingController')

    assert_equal(render_span.name, 'rails.render_template')
    assert_equal(render_span.span_type, 'template')
    assert_equal(render_span.service, Datadog.configuration[:rails][:service_name])
    assert_equal(render_span.resource, 'tracing/full.html.erb')
    assert_equal(render_span.get_tag('rails.template_name'), 'tracing/full.html.erb')

    adapter_name = get_adapter_name
    assert_equal(database_span.name, "#{adapter_name}.query")
    assert_equal(database_span.span_type, 'sql')
    assert_equal(database_span.service, adapter_name)
    assert_equal(adapter_name, database_span.get_tag('active_record.db.vendor'))
    assert_nil(database_span.get_tag('active_record.db.cached'))
    assert_includes(database_span.resource, 'SELECT')
    assert_includes(database_span.resource, 'FROM')
    assert_includes(database_span.resource, 'articles')

    if Datadog::Contrib::ActiveRecord::Events::Instantiation.supported?
      assert_equal(instantiation_span.name, 'active_record.instantiation')
      assert_equal(instantiation_span.span_type, 'custom')
      assert_equal(instantiation_span.service, Datadog.configuration[:rails][:service_name])
      assert_equal(instantiation_span.resource, 'Article')
      assert_equal(instantiation_span.get_tag('active_record.instantiation.class_name'), 'Article')
      assert_equal(instantiation_span.get_tag('active_record.instantiation.record_count'), 0)
    end

    assert_equal(cache_span.name, 'rails.cache')
    assert_equal(cache_span.span_type, 'cache')
    assert_equal(cache_span.resource, 'SET')
    assert_equal(cache_span.service, "#{app_name}-cache")
    assert_equal(cache_span.get_tag('rails.cache.backend').to_s, 'file_store')
    assert_equal(cache_span.get_tag('rails.cache.key'), 'empty-key')
  end

  test 'the rack.request span has the Rails exception' do
    # make a request that fails
    get '/error'
    assert_response :error

    # get spans
    spans = @tracer.writer.spans()
    assert_operator(spans.length, :>=, 2, 'there should be at least 2 spans')
    request_span, controller_span = spans

    assert_equal(controller_span.name, 'rails.action_controller')
    assert_equal(controller_span.status, 1)
    assert_equal(controller_span.get_tag('error.type'), 'ZeroDivisionError')
    assert_equal(controller_span.get_tag('error.msg'), 'divided by 0')
    refute_nil(controller_span.get_tag('error.stack')) # error stack is in rack span

    assert_equal('rack.request', request_span.name)
    assert_equal(request_span.span_type, 'web')
    assert_equal(request_span.resource, 'TracingController#error')
    assert_equal(request_span.get_tag('http.url'), '/error')
    assert_equal(request_span.get_tag('http.method'), 'GET')
    assert_equal(request_span.get_tag('http.status_code'), 500)
    assert_equal(request_span.status, 1, 'span should be flagged as an error')
    refute_nil(request_span.get_tag('error.stack')) # error stack is in rack span
    assert_match(/controllers\.rb.*error/, request_span.get_tag('error.stack'))
    assert_match(/\n/, request_span.get_tag('error.stack'))
  end

  test 'the rack.request span has the Rails exception, soft error version' do
    # make a request that fails
    get '/soft_error'
    # assert_response 520

    # get spans
    spans = @tracer.writer.spans()
    assert_operator(spans.length, :>=, 2, 'there should be at least 2 spans')
    request_span, controller_span = spans

    assert_equal(controller_span.name, 'rails.action_controller')
    assert_equal(controller_span.status, 1)
    assert_nil(controller_span.get_tag('error.type'))
    assert_nil(controller_span.get_tag('error.msg'))
    assert_nil(controller_span.get_tag('error.stack'))

    assert_equal('rack.request', request_span.name)
    assert_equal(request_span.span_type, 'web')
    assert_equal(request_span.resource, 'TracingController#soft_error')
    assert_equal(request_span.get_tag('http.url'), '/soft_error')
    assert_equal(request_span.get_tag('http.method'), 'GET')
    assert_equal(request_span.get_tag('http.status_code'), 520)
    assert_equal(request_span.status, 1, 'span should be flagged as an error')
    assert_nil(request_span.get_tag('error.stack'))
  end

  test 'the rack.request span has the Rails exception and call stack is correct' do
    # make a request that fails
    get '/sub_error'
    assert_response :error

    # get spans
    spans = @tracer.writer.spans()
    assert_operator(spans.length, :>=, 2, 'there should be at least 2 spans')
    request_span, controller_span = spans

    assert_equal(controller_span.name, 'rails.action_controller')
    assert_equal(controller_span.status, 1)
    assert_equal(controller_span.get_tag('error.type'), 'ZeroDivisionError')
    assert_equal(controller_span.get_tag('error.msg'), 'divided by 0')
    refute_nil(controller_span.get_tag('error.stack')) # error stack is in rack span

    assert_equal('rack.request', request_span.name)
    assert_equal(request_span.span_type, 'web')
    assert_equal(request_span.resource, 'TracingController#sub_error')
    assert_equal(request_span.get_tag('http.url'), '/sub_error')
    assert_equal(request_span.get_tag('http.method'), 'GET')
    assert_equal(request_span.get_tag('http.status_code'), 500)
    assert_equal(request_span.status, 1, 'span should be flagged as an error')
    assert_equal(controller_span.get_tag('error.type'), 'ZeroDivisionError')
    assert_equal(controller_span.get_tag('error.msg'), 'divided by 0')
    refute_nil(request_span.get_tag('error.stack')) # error stack is in rack span
    assert_match(/controllers\.rb.*error/, request_span.get_tag('error.stack'))
    assert_match(/controllers\.rb.*another_nested_error_call/, request_span.get_tag('error.stack'))
    assert_match(/controllers\.rb.*a_nested_error_call/, request_span.get_tag('error.stack'))
    assert_match(/controllers\.rb.*sub_error/, request_span.get_tag('error.stack'))
    assert_match(/\n/, request_span.get_tag('error.stack'))
  end

  test 'custom error controllers should not override trace resource names' do
    # Simulate an error being passed to the exception controller
    # (Syntax depends on Rails integration test version)
    if Rails.version >= '5.0'
      get '/internal_server_error', headers: { 'action_dispatch.exception' => ArgumentError.new }
    else
      get '/internal_server_error', {}, 'action_dispatch.exception' => ArgumentError.new
    end

    assert_response :error

    # Check spans
    spans = @tracer.writer.spans
    assert_equal(2, spans.length)

    rack_span = spans.first
    controller_span = spans.last

    # Rack span
    assert_equal(rack_span.status, 1, 'span should be flagged as an error')
    refute_equal(rack_span.resource, controller_span.resource) # We expect the resource hasn't been overriden

    # Controller span
    assert_equal(controller_span.status, 1, 'span should be flagged as an error')
    assert_equal(controller_span.resource, 'ErrorsController#internal_server_error')
  end

  test 'the status code is properly set if Rails controller is bypassed' do
    # make a request that doesn't have a route
    get '/not_existing'
    assert_response 404

    # get spans
    spans = @tracer.writer.spans()
    assert_operator(spans.length, :>=, 1, 'there should be at least 1 span')
    request_span = spans[0]

    assert_equal('rack.request', request_span.name)
    assert_equal(request_span.span_type, 'web')
    assert_equal(request_span.resource, 'GET 404')
    assert_equal(request_span.get_tag('http.url'), '/not_existing')
    assert_equal(request_span.get_tag('http.method'), 'GET')
    assert_equal(request_span.get_tag('http.status_code'), 404)
    assert_equal(request_span.status, 0)
  end
end
