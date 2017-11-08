require 'helper'
require 'ddtrace/tracer'
require 'ddtrace/context_flush'

class ContextFlushEachTest < Minitest::Test
  def test_each_partial_trace_typical_not_enough_traces
    tracer = get_test_tracer
    context_flush = Datadog::ContextFlush.new
    context = tracer.call_context

    context_flush.each_partial_trace(context) do |_t|
      flunk('nothing should be partially flushed, no spans')
    end

    # the plan:
    #
    # root-------------.
    #   | \______       \
    #   |        \       \
    # child1   child3   child4
    #   |                 |  \_____
    #   |                 |        \
    # child2            child5   child6

    tracer.trace('root') do
      tracer.trace('child1') do
        tracer.trace('child2') do
        end
      end
      tracer.trace('child3') do
        # finished spans are CAPITALIZED
        #
        # root
        #   | \______
        #   |        \
        # CHILD1   child3
        #   |
        #   |
        # CHILD2
        context_flush.each_partial_trace(context) do |t|
          flunk("nothing should be partially flushed, got: #{t}")
        end
      end
      tracer.trace('child4') do
        tracer.trace('child5') do
        end
        tracer.trace('child6') do
        end
      end
      # finished spans are CAPITALIZED
      #
      # root-------------.
      #   | \______       \
      #   |        \       \
      # CHILD1   CHILD3   CHILD4
      #   |                 |  \_____
      #   |                 |        \
      # CHILD2            CHILD5   CHILD6
      context_flush.each_partial_trace(context) do |t|
        flunk("nothing should be partially flushed, got: #{t}")
      end
    end

    context_flush.each_partial_trace(context) do |t|
      flunk("nothing should be partially flushed, got: #{t}")
    end

    assert_equal(0, context.length, 'everything should be written by now')
  end

  def test_each_partial_trace_typical
    tracer = get_test_tracer
    context_flush = Datadog::ContextFlush.new(min_spans_before_partial_flush: 1,
                                              max_spans_before_partial_flush: 1)
    context = tracer.call_context

    # the plan:
    #
    # root-------------.
    #   | \______       \
    #   |        \       \
    # child1   child3   child4
    #   |                 |  \_____
    #   |                 |        \
    # child2            child5   child6

    action12 = Minitest::Mock.new
    action12.expect(:call_with_names, nil, [%w[child1 child2].to_set])
    action3456 = Minitest::Mock.new
    action3456.expect(:call_with_names, nil, [['child3'].to_set])
    action3456.expect(:call_with_names, nil, [%w[child4 child5 child6].to_set])

    tracer.trace('root') do
      tracer.trace('child1') do
        tracer.trace('child2') do
        end
      end
      tracer.trace('child3') do
        # finished spans are CAPITALIZED
        #
        # root
        #   | \______
        #   |        \
        # CHILD1   child3
        #   |
        #   |
        # CHILD2
        context_flush.each_partial_trace(context) do |t|
          action12.call_with_names(t.map(&:name).to_set)
        end
      end
      tracer.trace('child4') do
        tracer.trace('child5') do
        end
        tracer.trace('child6') do
        end
      end
      # finished spans are CAPITALIZED
      #
      # root-------------.
      #     \______       \
      #            \       \
      #          CHILD3   CHILD4
      #                     |  \_____
      #                     |        \
      #                   CHILD5   CHILD6
      context_flush.each_partial_trace(context) do |t|
        action3456.call_with_names(t.map(&:name).to_set)
      end
    end

    action12.verify
    action3456.verify

    assert_equal(0, context.length, 'everything should be written by now')
  end

  # rubocop:disable Metrics/MethodLength
  def test_each_partial_trace_mixed
    tracer = get_test_tracer
    context_flush = Datadog::ContextFlush.new(min_spans_before_partial_flush: 1,
                                              max_spans_before_partial_flush: 1)
    context = tracer.call_context

    # the plan:
    #
    # root
    #   | \______
    #   |        \
    # child1   child5
    #   |
    #   |
    # child2
    #   | \______
    #   |        \
    # child3   child6
    #   |        |
    #   |        |
    # child4   child7

    action345 = Minitest::Mock.new
    action345.expect(:call_with_names, nil, [%w[child3 child4].to_set])
    action345.expect(:call_with_names, nil, [%w[child5].to_set])

    root = tracer.start_span('root', child_of: context)
    child1 = tracer.start_span('child1', child_of: root)
    child2 = tracer.start_span('child2', child_of: child1)
    child3 = tracer.start_span('child3', child_of: child2)
    child4 = tracer.start_span('child4', child_of: child3)
    child5 = tracer.start_span('child5', child_of: root)
    child6 = tracer.start_span('child6', child_of: child2)
    child7 = tracer.start_span('child7', child_of: child6)

    context_flush.each_partial_trace(context) do |_t|
      context_flush.each_partial_trace(context) do |_t|
        flunk('nothing should be partially flushed, no span is finished')
      end
    end

    assert_equal(8, context.length)

    [root, child1, child3, child6].each do |span|
      span.finish
      context_flush.each_partial_trace(context) do |t|
        flunk("nothing should be partially flushed, got: #{t}")
      end
    end

    # finished spans are CAPITALIZED
    #
    # ROOT
    #   | \______
    #   |        \
    # CHILD1   child5
    #   |
    #   |
    # child2
    #   | \______
    #   |        \
    # CHILD3   CHILD6
    #   |        |
    #   |        |
    # child4   child7

    child2.finish

    context_flush.each_partial_trace(context) do |t|
      flunk("nothing should be partially flushed, got: #{t}")
    end

    # finished spans are CAPITALIZED
    #
    # ROOT
    #   | \______
    #   |        \
    # CHILD1   child5
    #   |
    #   |
    # CHILD2
    #   | \______
    #   |        \
    # CHILD3   CHILD6
    #   |        |
    #   |        |
    # child4   child7

    child4.finish
    child5.finish

    # finished spans are CAPITALIZED
    #
    # ROOT
    #   | \______
    #   |        \
    # CHILD1   CHILD5
    #   |
    #   |
    # CHILD2
    #   | \______
    #   |        \
    # CHILD3   CHILD6
    #   |        |
    #   |        |
    # CHILD4   child7

    context_flush.each_partial_trace(context) do |t|
      action345.call_with_names(t.map(&:name).to_set)
    end

    child7.finish

    context_flush.each_partial_trace(context) do |t|
      flunk("nothing should be partially flushed, got: #{t}")
    end

    assert_equal(0, context.length, 'everything should be written by now')
  end
end

module Datadog
  class Tracer
    attr_accessor :context_flush
  end
end

class ContextFlushPartialTest < Minitest::Test
  MIN_SPANS = 10
  MAX_SPANS = 100
  TIMEOUT = 60 # make this very high to reduce test flakiness (1 minute here)

  def get_context_flush
    Datadog::ContextFlush.new(min_spans_before_partial_flush: MIN_SPANS,
                              max_spans_before_partial_flush: MAX_SPANS,
                              partial_flush_timeout: TIMEOUT)
  end

  # rubocop:disable Metrics/AbcSize
  def test_partial_caterpillar
    tracer = get_test_tracer
    context_flush = get_context_flush
    tracer.context_flush = context_flush

    write1 = Minitest::Mock.new
    expected = []
    MIN_SPANS.times do |i|
      expected << "a.#{i}"
    end
    (MAX_SPANS - MIN_SPANS).times do |i|
      expected << "b.#{i}"
    end
    # We need to sort the values the same way the values will be output by the test transport
    expected.sort!
    expected.each do |e|
      write1.expect(:call_with_name, nil, [e])
    end

    write2 = Minitest::Mock.new
    expected = ['root']
    MIN_SPANS.times do |i|
      expected << "b.#{i + MAX_SPANS - MIN_SPANS}"
    end
    # We need to sort the values the same way the values will be output by the test transport
    expected.sort!
    expected.each do |e|
      write2.expect(:call_with_name, nil, [e])
    end

    tracer.trace('root') do
      MIN_SPANS.times do |i|
        tracer.trace("a.#{i}") do
        end
      end
      spans = tracer.writer.spans()
      assert_equal(0, spans.length, 'nothing should be flushed, as max limit is not reached')
      MAX_SPANS.times do |i|
        tracer.trace("b.#{i}") do
        end
      end
      spans = tracer.writer.spans()
      # Let's explain the extra span here, what should happen is:
      # - root span is started
      # - then 99 spans (10 from 1st batch, 89 from second batch) are put in context
      # - then the 101th comes (the 90th from the second batch) and triggers a flush of everything but root span
      # - then the last 10 spans from second batch are thrown in, so that's 10 left + the root span
      assert_equal(1 + MIN_SPANS, tracer.call_context.length, 'some spans should have been sent')
      assert_equal(MAX_SPANS, spans.length)
      spans.each do |span|
        write1.call_with_name(span.name)
      end
      write1.verify
    end

    spans = tracer.writer.spans()
    assert_equal(MIN_SPANS + 1, spans.length)
    spans.each do |span|
      write2.call_with_name(span.name)
    end
    write2.verify
  end

  # Test the tracer configure args which are forwarded to context flush only.
  def test_tracer_configure
    tracer = get_test_tracer

    old_context_flush = tracer.context_flush
    tracer.configure()
    assert_equal(old_context_flush, tracer.context_flush, 'the same context_flush should be reused')

    tracer.configure(min_spans_before_partial_flush: 3,
                     max_spans_before_partial_flush: 3)

    refute_equal(old_context_flush, tracer.context_flush, 'another context_flush should be have been created')
  end

  def test_tracer_hard_limit_overrides_soft_limit
    tracer = get_test_tracer

    context = tracer.call_context
    tracer.configure(min_spans_before_partial_flush: context.max_length,
                     max_spans_before_partial_flush: context.max_length,
                     partial_flush_timeout: 3600)

    n = 1_000_000
    assert_operator(n, :>, context.max_length, 'need to send enough spans')
    tracer.trace('root') do
      n.times do |_i|
        tracer.trace('span.${i}') do
        end
        spans = tracer.writer.spans()
        assert_equal(0, spans.length, 'nothing should be written, soft limit is inhibited')
      end
    end
    spans = tracer.writer.spans()
    assert_equal(context.max_length, spans.length, 'size should be capped to hard limit')
  end
end
