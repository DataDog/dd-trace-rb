require('contrib/grape/app')
class TracedAPITest < BaseAPITest
  it('traced api success') do
    get('/base/success')
    expect(last_response.ok?).to(eq(true))
    expect(last_response.body).to(eq('OK'))
    spans = @tracer.writer.spans
    expect(2).to(eq(spans.length))
    render = spans[0]
    run = spans[1]
    expect('grape.endpoint_render').to(eq(render.name))
    expect('http').to(eq(render.span_type))
    expect('grape').to(eq(render.service))
    expect('grape.endpoint_render').to(eq(render.resource))
    expect(0).to(eq(render.status))
    expect(run).to(eq(render.parent))
    expect('grape.endpoint_run').to(eq(run.name))
    expect('http').to(eq(run.span_type))
    expect('grape').to(eq(run.service))
    expect('TestingAPI#success').to(eq(run.resource))
    expect(0).to(eq(run.status))
    expect(run.parent).to(be_nil)
  end
  it('traced api exception') do
    expect { get('/base/hard_failure') }.to(raise_error)
    spans = @tracer.writer.spans
    expect(2).to(eq(spans.length))
    render = spans[0]
    run = spans[1]
    expect('grape.endpoint_render').to(eq(render.name))
    expect('http').to(eq(render.span_type))
    expect('grape').to(eq(render.service))
    expect('grape.endpoint_render').to(eq(render.resource))
    expect(1).to(eq(render.status))
    expect('StandardError').to(eq(render.get_tag('error.type')))
    expect('Ouch!').to(eq(render.get_tag('error.msg')))
    assert_includes(render.get_tag('error.stack'), '<class:TestingAPI>')
    expect(run).to(eq(render.parent))
    expect('grape.endpoint_run').to(eq(run.name))
    expect('http').to(eq(run.span_type))
    expect('grape').to(eq(run.service))
    expect('TestingAPI#hard_failure').to(eq(run.resource))
    expect(1).to(eq(run.status))
    expect('StandardError').to(eq(run.get_tag('error.type')))
    expect('Ouch!').to(eq(run.get_tag('error.msg')))
    assert_includes(run.get_tag('error.stack'), '<class:TestingAPI>')
    expect(run.parent).to(be_nil)
  end
  it('traced api before after filters') do
    get('/filtered/before_after')
    expect(last_response.ok?).to(eq(true))
    expect(last_response.body).to(eq('OK'))
    spans = @tracer.writer.spans
    expect(4).to(eq(spans.length))
    render, run, before, after = spans
    expect('grape.endpoint_run_filters').to(eq(before.name))
    expect('http').to(eq(before.span_type))
    expect('grape').to(eq(before.service))
    expect('grape.endpoint_run_filters').to(eq(before.resource))
    expect(0).to(eq(before.status))
    expect(run).to(eq(before.parent))
    expect((before.to_hash[:duration] > 0.01)).to(be_truthy)
    expect('grape.endpoint_render').to(eq(render.name))
    expect('http').to(eq(render.span_type))
    expect('grape').to(eq(render.service))
    expect('grape.endpoint_render').to(eq(render.resource))
    expect(0).to(eq(render.status))
    expect(run).to(eq(render.parent))
    expect('grape.endpoint_run_filters').to(eq(after.name))
    expect('http').to(eq(after.span_type))
    expect('grape').to(eq(after.service))
    expect('grape.endpoint_run_filters').to(eq(after.resource))
    expect(0).to(eq(after.status))
    expect(run).to(eq(after.parent))
    expect((after.to_hash[:duration] > 0.01)).to(be_truthy)
    expect(run.name).to(eq('grape.endpoint_run'))
    expect(run.span_type).to(eq('http'))
    expect(run.service).to(eq('grape'))
    expect(run.resource).to(eq('TestingAPI#before_after'))
    expect(run.status).to(eq(0))
    expect(run.parent).to(be_nil)
  end
  it('traced api before after filters exceptions') do
    expect { get('/filtered_exception/before') }.to(raise_error)
    spans = @tracer.writer.spans
    expect(2).to(eq(spans.length))
    run, before = spans
    expect('grape.endpoint_run_filters').to(eq(before.name))
    expect('http').to(eq(before.span_type))
    expect('grape').to(eq(before.service))
    expect('grape.endpoint_run_filters').to(eq(before.resource))
    expect(1).to(eq(before.status))
    expect('StandardError').to(eq(before.get_tag('error.type')))
    expect('Ouch!').to(eq(before.get_tag('error.msg')))
    assert_includes(before.get_tag('error.stack'), '<class:TestingAPI>')
    expect(run).to(eq(before.parent))
    expect('grape.endpoint_run').to(eq(run.name))
    expect('http').to(eq(run.span_type))
    expect('grape').to(eq(run.service))
    expect('TestingAPI#before').to(eq(run.resource))
    expect(1).to(eq(run.status))
    expect(run.parent).to(be_nil)
  end
end
