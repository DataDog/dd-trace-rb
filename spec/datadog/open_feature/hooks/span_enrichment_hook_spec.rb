# frozen_string_literal: true

require 'spec_helper'

require 'json'
require 'digest'
require 'base64'

# Tests run under the openfeature appraisal which includes the real OpenFeature SDK
require 'open_feature/sdk'
require 'datadog/open_feature/hooks/span_enrichment_hook'

RSpec.describe Datadog::OpenFeature::Hooks::SpanEnrichmentHook do
  subject(:hook) { described_class.new(accumulator_store) }

  let(:accumulator_store) { Datadog::OpenFeature::Hooks::SpanEnrichmentHook::AccumulatorStore.new }

  # The local root span operation is resolved off the active trace at capture
  # time. Tests stub Datadog::Tracing.active_trace to control the seam.
  let(:trace_op) { Datadog::Tracing::TraceOperation.new }

  before { allow(Datadog::Tracing).to receive(:active_trace).and_return(trace_op) }

  describe '#capture' do
    it 'accumulates a serial id for the active root span' do
      hook.capture(flag_key: 'flag-a', variant: 'on', value: 'on', serial_id: 100, do_log: false, targeting_key: 'user-123')

      state = accumulator_store[trace_op]
      expect(state.has_data?).to be(true)
      expect(state.to_span_tags['ffe_flags_enc']).to eq('ZA==')
    end

    it 'adds a subject only when do_log is true and a targeting key is present' do
      hook.capture(flag_key: 'flag-a', variant: 'on', value: 'on', serial_id: 100, do_log: true, targeting_key: 'user-123')

      state = accumulator_store[trace_op]
      expect(state.to_span_tags).to have_key('ffe_subjects_enc')
    end

    it 'does not add a subject when do_log is false' do
      hook.capture(flag_key: 'flag-a', variant: 'on', value: 'on', serial_id: 100, do_log: false, targeting_key: 'user-123')

      state = accumulator_store[trace_op]
      expect(state.to_span_tags).not_to have_key('ffe_subjects_enc')
    end

    it 'detects a runtime default via a missing variant' do
      hook.capture(flag_key: 'flag-default', variant: nil, value: 'control', serial_id: nil, do_log: false, targeting_key: nil)

      state = accumulator_store[trace_op]
      defaults = JSON.parse(state.to_span_tags['ffe_runtime_defaults'])
      expect(defaults).to eq('flag-default' => 'control')
    end

    it 'does not raise when there is no active root span' do
      allow(Datadog::Tracing).to receive(:active_trace).and_return(nil)

      expect do
        hook.capture(flag_key: 'flag-a', variant: 'on', value: 'on', serial_id: 100, do_log: false, targeting_key: nil)
      end.not_to raise_error
    end

    it 'does not raise when capture hits an internal error (error isolation)' do
      allow(Datadog::Tracing).to receive(:active_trace).and_raise(StandardError, 'boom')

      expect do
        hook.capture(flag_key: 'flag-a', variant: 'on', value: 'on', serial_id: 100, do_log: false, targeting_key: nil)
      end.not_to raise_error
    end
  end

  describe 'root-span write integration' do
    it 'writes ffe_* tags on the local root span on finish and clears state' do
      trace_op.measure('root') do
        hook.capture(flag_key: 'flag-a', variant: 'on', value: 'on', serial_id: 100, do_log: true, targeting_key: 'user-123')
        hook.capture(flag_key: 'flag-default', variant: nil, value: 'control', serial_id: nil, do_log: false, targeting_key: nil)
      end

      expect(trace_op.get_tag('ffe_flags_enc')).to eq('ZA==')
      subjects = JSON.parse(trace_op.get_tag('ffe_subjects_enc'))
      expect(subjects[Digest::SHA256.hexdigest('user-123')]).to eq('ZA==')
      expect(JSON.parse(trace_op.get_tag('ffe_runtime_defaults'))).to eq('flag-default' => 'control')

      # State cleaned up after the root span finishes (no leak).
      expect(accumulator_store[trace_op]).to be_nil
    end

    it 'writes no tags when the finished root span accumulated no data' do
      trace_op.measure('root') do
        # No captures.
      end

      expect(trace_op.get_tag('ffe_flags_enc')).to be_nil
      expect(trace_op.get_tag('ffe_subjects_enc')).to be_nil
      expect(trace_op.get_tag('ffe_runtime_defaults')).to be_nil
    end

    # Regression: a child span finishing BEFORE the local root must not
    # destroy the trace's accumulated state. `span_before_finish` fires for every
    # span, and in any nested trace the child finishes first; cleanup must only
    # run when the local root is the span finishing, never on a child finish.
    it 'still writes ffe_* tags on the root when a child span finishes first' do
      trace_op.measure('root') do
        hook.capture(flag_key: 'flag-a', variant: 'on', value: 'on', serial_id: 100, do_log: true, targeting_key: 'user-123')

        # A nested child span that opens and finishes entirely inside the root.
        # Its `span_before_finish` fires before the root's, exercising the
        # child-finishes-first ordering.
        trace_op.measure('child') do
          # No additional captures inside the child — the point is only that the
          # child finishes (and publishes span_before_finish) before the root.
        end
      end

      # Despite the child finishing first, the root keeps the accumulated data.
      expect(trace_op.get_tag('ffe_flags_enc')).to eq('ZA==')
      subjects = JSON.parse(trace_op.get_tag('ffe_subjects_enc'))
      expect(subjects[Digest::SHA256.hexdigest('user-123')]).to eq('ZA==')

      # State is cleaned up exactly once, when the root finishes (no leak).
      expect(accumulator_store[trace_op]).to be_nil
    end

    # Companion to the above: a capture that happens AFTER a child has already
    # finished must also survive to the root write. This guards against keying or
    # cleanup that resurrects/drops state mid-trace.
    it 'writes ffe_* tags when a flag is evaluated after a child span finished' do
      trace_op.measure('root') do
        trace_op.measure('child') do
          # Child finishes first; no capture yet.
        end

        # Evaluate the flag only after the child has finished.
        hook.capture(flag_key: 'flag-a', variant: 'on', value: 'on', serial_id: 100, do_log: false, targeting_key: nil)
      end

      expect(trace_op.get_tag('ffe_flags_enc')).to eq('ZA==')
      expect(accumulator_store[trace_op]).to be_nil
    end
  end

  describe '#shutdown' do
    it 'clears all accumulated state' do
      hook.capture(flag_key: 'flag-a', variant: 'on', value: 'on', serial_id: 100, do_log: false, targeting_key: nil)
      expect(accumulator_store[trace_op]).not_to be_nil

      hook.shutdown

      expect(accumulator_store[trace_op]).to be_nil
    end

    # A trace that already subscribed keeps its accumulator alive via the
    # span_before_finish closure; shutting the hook down must not let that
    # in-flight trace emit stale ffe_* tags when its root span later finishes.
    it 'does not write tags on a root span that finishes after shutdown' do
      trace_op.measure('root') do
        hook.capture(flag_key: 'flag-a', variant: 'on', value: 'on', serial_id: 100, do_log: false, targeting_key: nil)
        hook.shutdown
      end

      expect(trace_op.get_tag('ffe_flags_enc')).to be_nil
    end
  end
end
