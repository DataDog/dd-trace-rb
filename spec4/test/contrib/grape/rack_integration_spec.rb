require('contrib/grape/rack_app')
class TracedRackAPITest < BaseRackAPITest
  it('traced api with rack') do
    get('/api/success')
    expect(last_response.ok?).to(eq(true))
    expect(last_response.body).to(eq('OK'))
    spans = @tracer.writer.spans
    expect(3).to(eq(spans.length))
    render = spans[0]
    run = spans[1]
    rack = spans[2]
    expect('grape.endpoint_render').to(eq(render.name))
    expect('http').to(eq(render.span_type))
    expect('grape').to(eq(render.service))
    expect('grape.endpoint_render').to(eq(render.resource))
    expect(0).to(eq(render.status))
    expect(run).to(eq(render.parent))
    expect('grape.endpoint_run').to(eq(run.name))
    expect('http').to(eq(run.span_type))
    expect('grape').to(eq(run.service))
    expect('RackTestingAPI#success').to(eq(run.resource))
    expect(0).to(eq(run.status))
    expect(rack).to(eq(run.parent))
    expect('rack.request').to(eq(rack.name))
    expect('http').to(eq(rack.span_type))
    expect('rack').to(eq(rack.service))
    expect('RackTestingAPI#success').to(eq(rack.resource))
    expect(0).to(eq(rack.status))
    expect(rack.parent).to(be_nil)
  end
  it('traced api failure with rack') do
    expect { get('/api/hard_failure') }.to(raise_error)
    spans = @tracer.writer.spans
    expect(3).to(eq(spans.length))
    render = spans[0]
    run = spans[1]
    rack = spans[2]
    expect('grape.endpoint_render').to(eq(render.name))
    expect('http').to(eq(render.span_type))
    expect('grape').to(eq(render.service))
    expect('grape.endpoint_render').to(eq(render.resource))
    expect(1).to(eq(render.status))
    expect('StandardError').to(eq(render.get_tag('error.type')))
    expect('Ouch!').to(eq(render.get_tag('error.msg')))
    assert_includes(render.get_tag('error.stack'), '<class:RackTestingAPI>')
    expect(run).to(eq(render.parent))
    expect('grape.endpoint_run').to(eq(run.name))
    expect('http').to(eq(run.span_type))
    expect('grape').to(eq(run.service))
    expect('RackTestingAPI#hard_failure').to(eq(run.resource))
    expect(1).to(eq(run.status))
    expect(rack).to(eq(run.parent))
    expect('rack.request').to(eq(rack.name))
    expect('http').to(eq(rack.span_type))
    expect('rack').to(eq(rack.service))
    expect('RackTestingAPI#hard_failure').to(eq(rack.resource))
    expect(1).to(eq(rack.status))
    expect(rack.parent).to(be_nil)
  end
  it('traced api 404 with rack') do
    get('/api/not_existing')
    spans = @tracer.writer.spans
    expect(1).to(eq(spans.length))
    rack = spans[0]
    expect('rack.request').to(eq(rack.name))
    expect('http').to(eq(rack.span_type))
    expect('rack').to(eq(rack.service))
    expect('GET 404').to(eq(rack.resource))
    expect(0).to(eq(rack.status))
    expect(rack.parent).to(be_nil)
  end
end
