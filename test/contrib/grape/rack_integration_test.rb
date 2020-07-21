require 'contrib/grape/rack_app'

# rubocop:disable Metrics/AbcSize
class TracedRackAPITest < BaseRackAPITest
  def test_traced_api_with_rack
    # it should play well with the Rack integration
    get '/api/success'
    assert last_response.ok?
    assert_equal('OK', last_response.body)

    assert_equal(spans.length, 3)
    render = spans[0]
    run = spans[1]
    rack = spans[2]

    assert_equal(render.name, 'grape.endpoint_render')
    assert_equal(render.span_type, 'template')
    assert_equal(render.service, 'grape')
    assert_equal(render.resource, 'grape.endpoint_render')
    assert_equal(render.status, 0)
    assert_equal(render.parent, run)

    assert_equal(run.name, 'grape.endpoint_run')
    assert_equal(run.span_type, 'web')
    assert_equal(run.service, 'grape')
    assert_equal(run.resource, 'RackTestingAPI#success')
    assert_equal(run.status, 0)
    assert_equal(run.parent, rack)

    assert_equal(rack.name, 'rack.request')
    assert_equal(rack.span_type, 'web')
    assert_equal(rack.service, 'rack')
    assert_equal(rack.resource, 'RackTestingAPI#success')
    assert_equal(rack.status, 0)
    assert_nil(rack.parent)
  end

  def test_traced_api_failure_with_rack
    # it should play well with the Rack integration even if an
    # exception is thrown
    assert_raises do
      get '/api/hard_failure'
    end

    assert_equal(spans.length, 3)
    render = spans[0]
    run = spans[1]
    rack = spans[2]

    assert_equal(render.name, 'grape.endpoint_render')
    assert_equal(render.span_type, 'template')
    assert_equal(render.service, 'grape')
    assert_equal(render.resource, 'grape.endpoint_render')
    assert_equal(render.status, 1)
    assert_equal(render.get_tag('error.type'), 'StandardError')
    assert_equal(render.get_tag('error.msg'), 'Ouch!')
    assert_includes(render.get_tag('error.stack'), 'grape/rack_app.rb')
    assert_equal(render.parent, run)

    assert_equal(run.name, 'grape.endpoint_run')
    assert_equal(run.span_type, 'web')
    assert_equal(run.service, 'grape')
    assert_equal(run.resource, 'RackTestingAPI#hard_failure')
    assert_equal(run.status, 1)
    assert_equal(run.parent, rack)

    assert_equal(rack.name, 'rack.request')
    assert_equal(rack.span_type, 'web')
    assert_equal(rack.service, 'rack')
    assert_equal(rack.resource, 'RackTestingAPI#hard_failure')
    assert_equal(rack.status, 1)
    assert_nil(rack.parent)
  end

  def test_traced_api_404_with_rack
    # it should not impact the Rack integration that must work as usual
    get '/api/not_existing'

    assert_equal(spans.length, 1)
    rack = spans[0]

    assert_equal(rack.name, 'rack.request')
    assert_equal(rack.span_type, 'web')
    assert_equal(rack.service, 'rack')
    assert_equal(rack.resource, 'GET 404')
    assert_equal(rack.status, 0)
    assert_nil(rack.parent)
  end
end
