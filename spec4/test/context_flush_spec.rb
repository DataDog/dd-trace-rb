require('helper')
require('ddtrace/tracer')
require('ddtrace/context_flush')

module Datadog
  class Tracer
    attr_accessor(:context_flush)
  end
end


RSpec.describe Datadog::ContextFlush do
  context 'partial flush with some data' do

  it('each partial trace typical not enough traces') do
    tracer = get_test_tracer
    context_flush = described_class.new
    context = tracer.call_context
    context_flush.each_partial_trace(context) do |_t|
      flunk('nothing should be partially flushed, no spans')
    end
    tracer.trace('root') do
      tracer.trace('child1') { tracer.trace('child2') {} }
      tracer.trace('child3') do
        context_flush.each_partial_trace(context) do |t|
          flunk("nothing should be partially flushed, got: #{t}")
        end
      end
      tracer.trace('child4') do
        tracer.trace('child5') {}
        tracer.trace('child6') {}
      end
      context_flush.each_partial_trace(context) do |t|
        flunk("nothing should be partially flushed, got: #{t}")
      end
    end
    context_flush.each_partial_trace(context) do |t|
      flunk("nothing should be partially flushed, got: #{t}")
    end
    expect(context.send(:length)).to(eq(0))
  end
  it('each partial trace typical') do
    tracer = get_test_tracer
    context_flush = described_class.new(min_spans_before_partial_flush: 1, max_spans_before_partial_flush: 1)
    context = tracer.call_context
    action12 = Minitest::Mock.new
    action12.expect(:call_with_names, nil, [%w[child1 child2].to_set])
    action3456 = Minitest::Mock.new
    action3456.expect(:call_with_names, nil, [['child3'].to_set])
    action3456.expect(:call_with_names, nil, [%w[child4 child5 child6].to_set])
    tracer.trace('root') do
      tracer.trace('child1') { tracer.trace('child2') {} }
      tracer.trace('child3') do
        context_flush.each_partial_trace(context) do |t|
          action12.call_with_names(t.map(&:name).to_set)
        end
      end
      tracer.trace('child4') do
        tracer.trace('child5') {}
        tracer.trace('child6') {}
      end
      context_flush.each_partial_trace(context) do |t|
        action3456.call_with_names(t.map(&:name).to_set)
      end
    end
    action12.verify
    action3456.verify
    expect(context.send(:length)).to(eq(0))
  end
  it('each partial trace mixed') do
    tracer = get_test_tracer
    context_flush = described_class.new(min_spans_before_partial_flush: 1, max_spans_before_partial_flush: 1)
    context = tracer.call_context
    action345 = Minitest::Mock.new
    action345.expect(:call_with_names, nil, [%w[child3 child4].to_set])
    action345.expect(:call_with_names, nil, [['child5'].to_set])
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
    expect(context.send(:length)).to(eq(8))
    [root, child1, child3, child6].each do |span|
      span.finish
      context_flush.each_partial_trace(context) do |t|
        flunk("nothing should be partially flushed, got: #{t}")
      end
    end
    child2.finish
    context_flush.each_partial_trace(context) do |t|
      flunk("nothing should be partially flushed, got: #{t}")
    end
    child4.finish
    child5.finish
    context_flush.each_partial_trace(context) do |t|
      action345.call_with_names(t.map(&:name).to_set)
    end
    child7.finish
    context_flush.each_partial_trace(context) do |t|
      flunk("nothing should be partially flushed, got: #{t}")
    end
    expect(context.send(:length)).to(eq(0))
  end
end

context 'partial flush with all data' do
  MIN_SPANS = 10
  MAX_SPANS = 100
  TIMEOUT = 60
  # make this very high to reduce test flakiness (1 minute here)
  def get_context_flush
    described_class.new(
      min_spans_before_partial_flush: MIN_SPANS,
      max_spans_before_partial_flush: MAX_SPANS,
      partial_flush_timeout: TIMEOUT
    )
  end
  it('partial caterpillar') do
    tracer = get_test_tracer
    context_flush = get_context_flush
    tracer.context_flush = context_flush
    write1 = Minitest::Mock.new
    expected = []
    MIN_SPANS.times { |i| (expected << "a.#{i}") }
    (MAX_SPANS - MIN_SPANS).times { |i| (expected << "b.#{i}") }
    expected.sort!
    expected.each { |e| write1.expect(:call_with_name, nil, [e]) }
    write2 = Minitest::Mock.new
    expected = ['root']
    MIN_SPANS.times { |i| (expected << "b.#{((i + MAX_SPANS) - MIN_SPANS)}") }
    expected.sort!
    expected.each { |e| write2.expect(:call_with_name, nil, [e]) }
    tracer.trace('root') do
      MIN_SPANS.times { |i| tracer.trace("a.#{i}") {} }
      spans = tracer.writer.spans
      expect(spans.length).to(eq(0))
      MAX_SPANS.times { |i| tracer.trace("b.#{i}") {} }
      spans = tracer.writer.spans
      expect(tracer.call_context.send(:length)).to(eq((1 + MIN_SPANS)))
      expect(spans.length).to(eq(MAX_SPANS))
      spans.each { |span| write1.call_with_name(span.name) }
      write1.verify
    end
    spans = tracer.writer.spans
    expect(spans.length).to(eq((MIN_SPANS + 1)))
    spans.each { |span| write2.call_with_name(span.name) }
    write2.verify
  end
  it('tracer configure') do
    tracer = get_test_tracer
    expect(tracer.context_flush).to(be_nil)
    flush_tracer = Datadog::Tracer.new(writer: FauxWriter.new, partial_flush: true)
    refute_nil(flush_tracer.context_flush)
    tracer.configure
    expect(tracer.context_flush).to(be_nil)
    tracer.configure(min_spans_before_partial_flush: 3, max_spans_before_partial_flush: 3)
    refute_nil(tracer.context_flush)
  end
  it('tracer hard limit overrides soft limit') do
    tracer = get_test_tracer
    context = tracer.call_context
    tracer.configure(
      min_spans_before_partial_flush: context.max_length,
      max_spans_before_partial_flush: context.max_length,
      partial_flush_timeout: 3600
    )
    n = 1000000
    assert_operator(n, :>, context.max_length, 'need to send enough spans')
    tracer.trace('root') do
      n.times do |_i|
        tracer.trace('span.${i}') {}
        spans = tracer.writer.spans
        expect(spans.length).to(eq(0))
      end
    end
    spans = tracer.writer.spans
    expect(spans.length).to(eq(context.max_length))
  end
end
end