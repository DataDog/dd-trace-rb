require('spec_helper')
require('ddtrace/tracer')
RSpec.describe 'concurrent task' do
  def traced_task
    @tracer.trace('a-root-task') do |_root_span|
      delay = rand
      @tracer.trace('a-sub-task') { |sub_span| sub_span.set_tag('delay', delay) }
      sleep(delay)
    end
    @tracer.writer.trace0_spans
  end
  it('parallel tasks') do
    @tracer = get_test_tracer
    semaphore = Mutex.new
    threads = []
    traces = []
    3.times do |_i|
      100.times do
        thr = Thread.new do
          trace = traced_task
          semaphore.synchronize { (traces << trace) }
        end
        (threads << thr)
      end
      threads.each(&:join)
    end
    expect(traces.length).to(eq(300))
    traces.each do |trace|
      expect(trace.length).to(eq(2))
      trace.sort! { |a, b| (a.name <=> b.name) }
      root, sub = trace
      expect(root.name).to(eq('a-root-task'))
      expect(sub.name).to(eq('a-sub-task'))
      expect(root.span_id).to_not(eq(root.trace_id))
      expect(sub.trace_id).to(eq(root.trace_id))
      expect(sub.parent_id).to(eq(root.span_id))
    end
  end
end
