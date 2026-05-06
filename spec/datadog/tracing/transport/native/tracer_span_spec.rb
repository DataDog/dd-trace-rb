# frozen_string_literal: true

require 'datadog/core'
require 'datadog/tracing/span'

RSpec.describe 'Datadog::Tracing::Transport::Native::TracerSpan' do
  before do
    skip_if_libdatadog_not_supported
  end

  let(:native_module) { Datadog::Tracing::Transport::Native }
  let(:tracer_span_class) { native_module::TracerSpan }

  # ---------------------------------------------------------------------------
  # Helper: create a populated Ruby span
  # ---------------------------------------------------------------------------

  let(:now) { Time.now }
  let(:trace_id_128bit) { (1 << 64) | 0xdeadbeef }

  def make_ruby_span(overrides = {})
    defaults = {
      service: 'test-service',
      resource: 'GET /test',
      type: 'web',
      id: 12345,
      parent_id: 67890,
      trace_id: trace_id_128bit,
      start_time: now,
      duration: 0.025,
      status: 0,
      meta: { 'http.method' => 'GET', 'http.url' => '/test' },
      metrics: { '_dd.measured' => 1.0, '_sampling_priority_v1' => 2.0 },
    }
    Datadog::Tracing::Span.new('web.request', **defaults.merge(overrides))
  end

  # ---------------------------------------------------------------------------
  # Tests
  # ---------------------------------------------------------------------------

  describe '._native_from_span' do
    context 'with a minimal span' do
      it 'returns a TracerSpan' do
        span = Datadog::Tracing::Span.new('test.op')
        result = tracer_span_class._native_from_span(span)
        expect(result).to be_a(tracer_span_class)
      end
    end

    context 'with all fields populated' do
      it 'returns a TracerSpan' do
        result = tracer_span_class._native_from_span(make_ruby_span)
        expect(result).to be_a(tracer_span_class)
      end
    end

    context 'with nil-able string fields set to nil' do
      it 'does not raise' do
        span = make_ruby_span(service: nil, type: nil)
        expect { tracer_span_class._native_from_span(span) }.not_to raise_error
      end
    end

    context 'with empty meta and metrics hashes' do
      it 'does not raise' do
        span = make_ruby_span(meta: {}, metrics: {})
        expect { tracer_span_class._native_from_span(span) }.not_to raise_error
      end
    end

    context 'with an unstarted span (no start_time or duration)' do
      it 'does not raise' do
        span = make_ruby_span(start_time: nil, duration: nil)
        expect { tracer_span_class._native_from_span(span) }.not_to raise_error
      end
    end

    context 'with a 128-bit trace ID' do
      it 'does not raise' do
        big_id = (0xaabbccdd << 64) | 0x11223344
        span = make_ruby_span(trace_id: big_id)
        expect { tracer_span_class._native_from_span(span) }.not_to raise_error
      end
    end

    context 'with a 64-bit trace ID (high bits zero)' do
      it 'does not raise' do
        span = make_ruby_span(trace_id: 42)
        expect { tracer_span_class._native_from_span(span) }.not_to raise_error
      end
    end

    context 'with non-string meta values (mixed hash)' do
      it 'silently skips non-string entries' do
        span = make_ruby_span(meta: { 'good' => 'value', 'bad' => 123, nil => 'also_bad' })
        expect { tracer_span_class._native_from_span(span) }.not_to raise_error
      end
    end

    context 'with non-numeric metrics values (mixed hash)' do
      it 'silently skips non-numeric entries' do
        span = make_ruby_span(metrics: { '_dd.measured' => 1.0, 'bad' => 'string' })
        expect { tracer_span_class._native_from_span(span) }.not_to raise_error
      end
    end

    context 'when called multiple times on the same span' do
      it 'returns independent instances' do
        span = make_ruby_span
        r1 = tracer_span_class._native_from_span(span)
        r2 = tracer_span_class._native_from_span(span)
        expect(r1).to be_a(tracer_span_class)
        expect(r2).to be_a(tracer_span_class)
        expect(r1).not_to equal(r2)
      end
    end

    context 'GC safety' do
      it 'does not crash when instances are garbage collected' do
        20.times { tracer_span_class._native_from_span(make_ruby_span) }
        GC.start
        GC.start
      end
    end

    it 'cannot be allocated directly' do
      expect { tracer_span_class.new }.to raise_error(TypeError)
    end
  end
end
