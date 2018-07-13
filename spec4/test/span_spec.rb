require('spec_helper')
require('ddtrace/span')
RSpec.describe Datadog::Span do
  it('span finish') do
    tracer = nil
    span = described_class.new(tracer, 'my.op')
    expect(span.start_time).to(be_nil)
    expect(span.end_time).to(be_nil)
    span.finish
    sleep(0.001)
    expect((span.end_time < Time.now.utc)).to(be_truthy)
    expect((span.start_time <= span.end_time)).to(be_truthy)
    expect((span.to_hash[:duration] >= 0)).to(be_truthy)
  end
  it('span finish once') do
    span = described_class.new(nil, 'span.test')
    sleep(0.001)
    span.finish
    end_time = span.end_time
    sleep(0.001)
    span.finish
    expect(end_time).to(eq(span.end_time))
  end
  it('span finish at') do
    span = described_class.new(nil, 'span.test')
    now = Time.now.utc
    sleep(0.01)
    span.finish(now)
    expect(now).to(eq(span.end_time))
  end
  it('span finish at once') do
    span = described_class.new(nil, 'span.test')
    now = Time.now.utc
    sleep(0.01)
    span.finish(now)
    span.finish(Time.now.utc)
    expect(now).to(eq(span.end_time))
  end
  it('span finished') do
    span = described_class.new(nil, 'span.test')
    expect(!span.finished?).to(be_truthy)
    span.finish
    expect(span.finished?).to(eq(true))
  end
  it('span ids') do
    span = described_class.new(nil, 'my.op')
    expect(span.span_id).to(be_truthy)
    expect(span.parent_id.zero?).to(eq(true))
    expect((span.trace_id != span.span_id)).to(be_truthy)
    expect('my.op').to(eq(span.name))
    expect(span.span_id.nonzero?).to(eq(true))
    expect(span.trace_id.nonzero?).to(eq(true))
  end
  it('span with parent') do
    span = described_class.new(nil, 'my.op', parent_id: 12, trace_id: 13)
    expect(span.span_id).to(be_truthy)
    expect(12).to(eq(span.parent_id))
    expect(13).to(eq(span.trace_id))
    expect('my.op').to(eq(span.name))
  end
  it('span set parent') do
    parent = described_class.new(nil, 'parent.span')
    child = described_class.new(nil, 'child.span')
    child.set_parent(parent)
    expect(parent).to(eq(child.parent))
    expect(parent.trace_id).to(eq(child.trace_id))
    expect(parent.span_id).to(eq(child.parent_id))
    expect(child.service).to(be_nil)
    expect(parent.service).to(be_nil)
  end
  it('span set parent keep service') do
    parent = described_class.new(nil, 'parent.span', service: 'webapp')
    child = described_class.new(nil, 'child.span', service: 'defaultdb')
    child.set_parent(parent)
    expect(parent).to(eq(child.parent))
    expect(parent.trace_id).to(eq(child.trace_id))
    expect(parent.span_id).to(eq(child.parent_id))
    expect('webapp').to_not(eq(child.service))
    expect('defaultdb').to(eq(child.service))
  end
  it('span set parent nil') do
    parent = described_class.new(nil, 'parent.span', service: 'webapp')
    child = described_class.new(nil, 'child.span', service: 'defaultdb')
    child.set_parent(parent)
    child.set_parent(nil)
    expect(child.parent).to(be_nil)
    expect(child.span_id).to(eq(child.trace_id))
    expect(0).to(eq(child.parent_id))
    expect('defaultdb').to(eq(child.service))
  end
  it('get valid metric') do
    span = described_class.new(nil, 'test.span')
    span.set_metric('a', 10)
    expect(span.get_metric('a')).to(eq(10.0))
  end
  it('set valid metrics') do
    span = described_class.new(nil, 'test.span')
    span.set_metric('a', 0)
    span.set_metric('b', -12)
    span.set_metric('c', 12.134)
    span.set_metric('d', 1231543543265475686787869123)
    span.set_metric('e', '12.34')
    h = span.to_hash
    expected = { 'a' => 0.0, 'b' => -12.0, 'c' => 12.134, 'd' => 1.2315435432654757e+27, 'e' => 12.34 }
    expect(h[:metrics]).to(eq(expected))
  end
  it('invalid metrics') do
    span = described_class.new(nil, 'test.span')
    span.set_metric('a', nil)
    span.set_metric('b', {})
    span.set_metric('c', [])
    span.set_metric('d', span)
    span.set_metric('e', 'a_string')
    h = span.to_hash
    expect(h[:metrics]).to(eq({}))
  end
  it('set error') do
    span = described_class.new(nil, 'test.span')
    error = RuntimeError.new('Something broke!')
    error.set_backtrace(%w[list of calling methods])
    displayed_backtrace = "list\nof\ncalling\nmethods\n".chomp
    span.set_error(error)
    expect(span.get_tag('error.msg')).to(eq('Something broke!'))
    expect(span.get_tag('error.type')).to(eq('RuntimeError'))
    expect(span.get_tag('error.stack')).to(eq(displayed_backtrace))
  end
end
