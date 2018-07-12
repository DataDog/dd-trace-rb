require('helper')
require('ddtrace/tracer')
RSpec.describe 'Tracer test' do
  it('trace') do
    tracer = get_test_tracer
    ret = tracer.trace('something') do |s|
      expect('something').to(eq(s.name))
      expect(s.end_time).to(be_nil)
      sleep(0.001)
      :return_val
    end
    expect(:return_val).to(eq(ret))
    spans = tracer.writer.spans
    expect(1).to(eq(spans.length))
    span = spans[0]
    expect('something').to(eq(span.name))
    expect((span.to_hash[:duration] > 0)).to(be_truthy)
  end
  it('trace no block') do
    tracer = get_test_tracer
    span = tracer.trace('something')
    expect(!span.nil?).to(be_truthy)
    expect('something').to(eq(span.name))
  end
  it('trace error') do
    tracer = get_test_tracer
    expect do
      tracer.trace('something') do |s|
        expect(s.end_time).to(be_nil)
        (1 / 0)
      end
    end.to(raise_error(ZeroDivisionError))
    spans = tracer.writer.spans
    expect(1).to(eq(spans.length))
    span = spans[0]
    expect(!span.end_time.nil?).to(be_truthy)
    expect('something').to(eq(span.name))
    expect('divided by 0').to(eq(span.get_tag('error.msg')))
    expect('ZeroDivisionError').to(eq(span.get_tag('error.type')))
    expect(span.get_tag('error.stack').include?('tracer_test.rb')).to(eq(true))
  end
  it('trace non standard error') do
    tracer = get_test_tracer
    expect do
      tracer.trace('something') do |s|
        expect(s.end_time).to(be_nil)
        raise(NoMemoryError)
      end
    end.to(raise_error(NoMemoryError))
    spans = tracer.writer.spans
    expect(1).to(eq(spans.length))
    span = spans[0]
    expect(!span.end_time.nil?).to(be_truthy)
    expect('something').to(eq(span.name))
    expect('NoMemoryError').to(eq(span.get_tag('error.msg')))
    expect('NoMemoryError').to(eq(span.get_tag('error.type')))
    expect(span.get_tag('error.stack').include?('tracer_test.rb')).to(eq(true))
  end
  it('trace child') do
    tracer = get_test_tracer
    tracer.trace('a', service: 'parent') do
      tracer.trace('b') { |s| s.set_tag('a', 'a') }
      tracer.trace('c', service: 'other') { |s| s.set_tag('b', 'b') }
    end
    spans = tracer.writer.spans
    expect(3).to(eq(spans.length))
    a, b, c = spans
    expect('a').to(eq(a.name))
    expect('b').to(eq(b.name))
    expect('c').to(eq(c.name))
    expect(b.trace_id).to(eq(a.trace_id))
    expect(c.trace_id).to(eq(a.trace_id))
    expect(b.parent_id).to(eq(a.span_id))
    expect(c.parent_id).to(eq(a.span_id))
    expect('parent').to(eq(a.service))
    expect('parent').to(eq(b.service))
    expect('other').to(eq(c.service))
  end
  it('trace child finishing after parent') do
    tracer = get_test_tracer
    t1 = tracer.trace('t1')
    t1_child = tracer.trace('t1_child')
    expect(t1).to(eq(t1_child.parent))
    t1.finish
    t1_child.finish
    t2 = tracer.trace('t2')
    expect(t2.parent).to(be_nil)
  end
  it('trace no block not finished') do
    tracer = get_test_tracer
    span = tracer.trace('something')
    expect(span.end_time).to(be_nil)
  end
  it('set service info') do
    tracer = get_test_tracer
    tracer.set_service_info('rest-api', 'rails', 'web')
    expect('app' => 'rails', 'app_type' => 'web').to(eq(tracer.services['rest-api']))
  end
  it('set tags') do
    tracer = get_test_tracer
    tracer.set_tags('env' => 'test', 'component' => 'core')
    expect('test').to(eq(tracer.tags['env']))
    expect('core').to(eq(tracer.tags['component']))
  end
  it('trace global tags') do
    tracer = get_test_tracer
    tracer.set_tags('env' => 'test', 'component' => 'core')
    span = tracer.trace('something')
    expect('test').to(eq(span.get_tag('env')))
    expect('core').to(eq(span.get_tag('component')))
  end
  it('disabled tracer') do
    tracer = get_test_tracer
    tracer.enabled = false
    tracer.trace('something').finish
    spans = tracer.writer.spans
    expect(spans.length).to(eq(0))
  end
  it('configure tracer') do
    tracer = get_test_tracer
    tracer.configure(enabled: false, hostname: 'agent.datadoghq.com', port: '8888')
    expect(false).to(eq(tracer.enabled))
    expect('agent.datadoghq.com').to(eq(tracer.writer.transport.hostname))
    expect('8888').to(eq(tracer.writer.transport.port))
  end
  it('default service') do
    tracer = get_test_tracer
    expect(tracer.default_service).to(eq('rake_test_loader'))
    old_service = tracer.default_service
    tracer.default_service = 'foo-bar'
    expect(tracer.default_service).to(eq('foo-bar'))
    tracer.default_service = old_service
  end
  it('active span') do
    tracer = get_test_tracer
    span = tracer.trace('something')
    expect(tracer.active_span).to(eq(span))
    expect(tracer.active_span.finished?).to(eq(false))
  end
  it('trace all args') do
    tracer = get_test_tracer
    tracer.set_tags('env' => 'test', 'temp' => 'cool')
    tracer.trace('op',
                 service: 'special-service',
                 resource: 'extra-resource',
                 span_type: 'my-type',
                 tags: { 'tag1' => 'value1', 'tag2' => 'value2' }) {}
    spans = tracer.writer.spans
    expect(spans.length).to(eq(1))
    span = spans[0]
    expect(span.service).to(eq('special-service'))
    expect(span.resource).to(eq('extra-resource'))
    expect(span.span_type).to(eq('my-type'))
    expect(span.meta.length).to(eq(5))
    expect(span.get_tag('env')).to(eq('test'))
    expect(span.get_tag('temp')).to(eq('cool'))
    expect(span.get_tag('tag1')).to(eq('value1'))
    expect(span.get_tag('tag2')).to(eq('value2'))
    expect(span.meta.key?('system.pid')).to(eq(true))
  end
  it('start span all args') do
    tracer = get_test_tracer
    tracer.set_tags('env' => 'test', 'temp' => 'cool')
    yesterday = (Time.now.utc - ((24 * 60) * 60))
    span = tracer.start_span('op',
                             service: 'special-service',
                             resource: 'extra-resource',
                             span_type: 'my-type',
                             start_time: yesterday,
                             tags: { 'tag1' => 'value1', 'tag2' => 'value2' })
    span.finish
    spans = tracer.writer.spans
    expect(spans.length).to(eq(1))
    span = spans[0]
    expect(span.service).to(eq('special-service'))
    expect(span.resource).to(eq('extra-resource'))
    expect(span.span_type).to(eq('my-type'))
    expect(span.start_time).to(eq(yesterday))
    expect(span.get_tag('env')).to(eq('test'))
    expect(span.get_tag('temp')).to(eq('cool'))
    expect(span.get_tag('tag1')).to(eq('value1'))
    expect(span.get_tag('tag2')).to(eq('value2'))
  end
  it('start span child of span') do
    tracer = get_test_tracer
    root = tracer.start_span('a')
    root.finish
    spans = tracer.writer.spans
    expect(spans.length).to(eq(1))
    a = spans[0]
    tracer.trace('b') do
      span = tracer.start_span('c', child_of: root)
      span.finish
    end
    spans = tracer.writer.spans
    expect(spans.length).to(eq(2))
    b, c = spans
    expect(b.trace_id).to_not(eq(a.trace_id))
    expect(c.trace_id).to_not(eq(b.trace_id))
    expect(c.trace_id).to(eq(a.trace_id))
    expect(c.parent_id).to(eq(a.span_id))
  end
  it('start span child of context') do
    tracer = get_test_tracer
    mutex = Mutex.new
    hold = Mutex.new
    @thread_span = nil
    @thread_ctx = nil
    hold.lock
    thread = Thread.new do
      mutex.synchronize do
        @thread_span = tracer.start_span('a')
        @thread_ctx = @thread_span.context
      end
      hold.lock
      hold.unlock
    end
    1000.times do
      mutex.synchronize { break unless @thread_ctx.nil? || @thread_span.nil? }
      sleep(0.01)
    end
    expect(tracer.call_context).to_not(eq(@thread_ctx))
    tracer.trace('b') do
      span = tracer.start_span('c', child_of: @thread_ctx)
      span.finish
    end
    @thread_span.finish
    hold.unlock
    thread.join
    @thread_span = nil
    @thread_ctx = nil
    spans = tracer.writer.spans
    expect(spans.length).to(eq(3))
    a, b, c = spans
    expect(b.trace_id).to_not(eq(a.trace_id))
    expect(c.trace_id).to_not(eq(b.trace_id))
    expect(c.trace_id).to(eq(a.trace_id))
    expect(c.parent_id).to(eq(a.span_id))
  end
  it('start span detach') do
    tracer = get_test_tracer
    main = tracer.trace('main_call')
    detached = tracer.start_span('detached_trace')
    detached.finish
    main.finish
    spans = tracer.writer.spans
    expect(spans.length).to(eq(2))
    d, m = spans
    expect(m.name).to(eq('main_call'))
    expect(d.name).to(eq('detached_trace'))
    expect(m.trace_id).to_not(eq(d.trace_id))
    expect(m.span_id).to_not(eq(d.parent_id))
    expect(m.parent_id).to(eq(0))
    expect(d.parent_id).to(eq(0))
  end
  it('trace nil resource') do
    tracer = get_test_tracer
    tracer.trace('resource_set_to_nil', resource: nil) do |s|
      expect(s.resource).to(be_nil)
    end
    tracer.trace('resource_set_to_default') { |s| }
    spans = tracer.writer.spans
    expect(2).to(eq(spans.length))
    resource_set_to_default, resource_set_to_nil = spans
    expect(resource_set_to_nil.resource).to(be_nil)
    expect(resource_set_to_nil.name).to(eq('resource_set_to_nil'))
    expect(resource_set_to_default.resource).to(eq('resource_set_to_default'))
    expect(resource_set_to_default.name).to(eq('resource_set_to_default'))
  end
  it('root span has pid metadata') do
    tracer = get_test_tracer
    root = tracer.trace('something')
    expect(root.get_tag('system.pid')).to(eq(Process.pid.to_s))
  end
  it('child span has no pid metadata') do
    tracer = get_test_tracer
    tracer.trace('something')
    child = tracer.trace('something_else')
    expect(child.get_tag('system.pid')).to(be_nil)
  end
  it('provider') do
    provider = Datadog::DefaultContextProvider.new
    tracer = Datadog::Tracer.new(context_provider: provider)
    assert_same(provider, tracer.provider)
  end
end
