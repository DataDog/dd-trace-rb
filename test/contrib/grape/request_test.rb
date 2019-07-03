require 'contrib/grape/app'

# rubocop:disable Metrics/AbcSize
class TracedAPITest < BaseAPITest
  def test_traced_api_success
    # it should trace the endpoint body
    get '/base/success'
    assert last_response.ok?
    assert_equal('OK', last_response.body)

    spans = @tracer.writer.spans()
    assert_equal(spans.length, 2)
    render = spans[0]
    run = spans[1]

    assert_equal(render.name, 'grape.endpoint_render')
    assert_equal(render.span_type, 'template')
    assert_equal(render.service, 'grape')
    assert_equal(render.resource, 'grape.endpoint_render')
    assert_equal(render.status, 0)
    assert_equal(render.parent, run)

    assert_equal(run.name, 'grape.endpoint_run')
    assert_equal(run.span_type, 'web')
    assert_equal(run.service, 'grape')
    assert_equal(run.resource, 'TestingAPI#success')
    assert_equal(run.status, 0)
    assert_nil(run.parent)
  end

  def test_traced_api_exception
    # it should handle exceptions
    assert_raises do
      get '/base/hard_failure'
    end

    spans = @tracer.writer.spans()
    assert_equal(spans.length, 2)
    render = spans[0]
    run = spans[1]

    assert_equal(render.name, 'grape.endpoint_render')
    assert_equal(render.span_type, 'template')
    assert_equal(render.service, 'grape')
    assert_equal(render.resource, 'grape.endpoint_render')
    assert_equal(render.status, 1)
    assert_equal(render.get_tag('error.type'), 'StandardError')
    assert_equal(render.get_tag('error.msg'), 'Ouch!')
    assert_includes(render.get_tag('error.stack'), '<class:TestingAPI>')
    assert_equal(render.parent, run)

    assert_equal(run.name, 'grape.endpoint_run')
    assert_equal(run.span_type, 'web')
    assert_equal(run.service, 'grape')
    assert_equal(run.resource, 'TestingAPI#hard_failure')
    assert_equal(run.status, 1)
    assert_equal(run.get_tag('error.type'), 'StandardError')
    assert_equal(run.get_tag('error.msg'), 'Ouch!')
    assert_includes(run.get_tag('error.stack'), '<class:TestingAPI>')
    assert_nil(run.parent)
  end

  def test_traced_api_4xx_exception_report_no_error
    Datadog.configure do |c|
      c.use :grape, error_for_4xx: false
    end
    post '/base/hard_failure'

    spans = @tracer.writer.spans()
    render = spans[0]
    assert_equal(render.status, 0)

    Datadog.configure do |c|
      c.use :grape, error_for_4xx: true
    end
  end

  def test_mine_4xx_exception_report_error
    post '/base/hard_failure'

    spans = @tracer.writer.spans()
    render = spans[0]
    assert_equal(render.status, 1)
  end

  def test_traced_api_before_after_filters
    # it should trace the endpoint body and all before/after filters
    get '/filtered/before_after'
    assert last_response.ok?
    assert_equal('OK', last_response.body)

    spans = @tracer.writer.spans()
    assert_equal(spans.length, 4)

    render, run, before, after = spans

    assert_equal(before.name, 'grape.endpoint_run_filters')
    assert_equal(before.span_type, 'web')
    assert_equal(before.service, 'grape')
    assert_equal(before.resource, 'grape.endpoint_run_filters')
    assert_equal(before.status, 0)
    assert_equal(before.parent, run)
    assert(before.to_hash[:duration] > 0.01)

    assert_equal(render.name, 'grape.endpoint_render')
    assert_equal(render.span_type, 'template')
    assert_equal(render.service, 'grape')
    assert_equal(render.resource, 'grape.endpoint_render')
    assert_equal(render.status, 0)
    assert_equal(render.parent, run)

    assert_equal(after.name, 'grape.endpoint_run_filters')
    assert_equal(after.span_type, 'web')
    assert_equal(after.service, 'grape')
    assert_equal(after.resource, 'grape.endpoint_run_filters')
    assert_equal(after.status, 0)
    assert_equal(after.parent, run)
    assert(after.to_hash[:duration] > 0.01)

    assert_equal('grape.endpoint_run', run.name)
    assert_equal('web', run.span_type)
    assert_equal('grape', run.service)
    assert_equal('TestingAPI#before_after', run.resource)
    assert_equal(0, run.status)
    assert_nil(run.parent)
  end

  def test_traced_api_before_after_filters_exceptions
    # it should trace the endpoint even if a filter raises an exception
    assert_raises do
      get '/filtered_exception/before'
    end

    spans = @tracer.writer.spans()
    assert_equal(spans.length, 2)

    run, before = spans

    assert_equal(before.name, 'grape.endpoint_run_filters')
    assert_equal(before.span_type, 'web')
    assert_equal(before.service, 'grape')
    assert_equal(before.resource, 'grape.endpoint_run_filters')
    assert_equal(before.status, 1)
    assert_equal(before.get_tag('error.type'), 'StandardError')
    assert_equal(before.get_tag('error.msg'), 'Ouch!')
    assert_includes(before.get_tag('error.stack'), '<class:TestingAPI>')
    assert_equal(before.parent, run)

    assert_equal(run.name, 'grape.endpoint_run')
    assert_equal(run.span_type, 'web')
    assert_equal(run.service, 'grape')
    assert_equal(run.resource, 'TestingAPI#before')
    assert_equal(run.status, 1)
    assert_nil(run.parent)
  end
end
