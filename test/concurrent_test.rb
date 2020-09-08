require 'helper'
require 'ddtrace/tracer'

class ConcurrentTest < Minitest::Test
  def setup
    # Ensure library is initialized in the main thread first
    Datadog.configure
  end

  def traced_task
    @tracer.trace('a-root-task') do |_root_span|
      delay = rand()
      @tracer.trace('a-sub-task') do |sub_span|
        sub_span.set_tag('delay', delay)
      end
      # the delay *must* be between the instant the sub-span finishes
      # and the instant the root span is done.
      sleep delay
    end
    @tracer.writer.trace0_spans()
  end

  def test_parallel_tasks
    @tracer = get_test_tracer

    semaphore = Mutex.new
    threads = []
    traces = []

    3.times do |_i|
      100.times do
        thr = Thread.new do
          trace = traced_task
          semaphore.synchronize do
            traces << trace
          end
        end
        threads << thr
      end
      threads.each(&:join)
    end

    assert_equal(300, traces.length)
    traces.each do |trace|
      assert_equal(2, trace.length)
      trace.sort! { |a, b| a.name <=> b.name }
      root, sub = trace
      assert_equal('a-root-task', root.name)
      assert_equal('a-sub-task', sub.name)
      refute_equal(root.trace_id, root.span_id)
      assert_equal(root.trace_id, sub.trace_id, 'root span and sub span must have the same trace id')
      assert_equal(root.span_id, sub.parent_id)
    end
  end
end
