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

  describe 'codec' do
    let(:codec) { Datadog::OpenFeature::Hooks::SpanEnrichmentHook::Codec }

    it 'encodes the golden vector' do
      expect(codec.encode_delta_varint(Set[100, 108, 128, 130])).to eq('ZAgUAg==')
    end

    it 'encodes an empty set to an empty string (tag omitted)' do
      expect(codec.encode_delta_varint(Set[])).to eq('')
    end

    it 'dedupes and sorts before encoding (Set semantics, order-independent)' do
      expect(codec.encode_delta_varint(Set[130, 100, 128, 108, 100])).to eq('ZAgUAg==')
    end

    # Regression: a delta >= 0x80 produces a varint with a continuation byte (>= 0x80).
    # The byte buffer must be binary; a UTF-8 buffer would re-encode 0x88 as the 2-byte
    # sequence 0xC2 0x88, so serial 2312 (bytes 88 12) would corrupt to 296002 on decode.
    it 'encodes serial ids with continuation bytes (>= 0x80) as raw bytes' do
      encoded = codec.encode_delta_varint(Set[2312])
      expect(encoded).to eq('iBI=')
      expect(Base64.strict_decode64(encoded).bytes).to eq([0x88, 0x12])
    end

    it 'round-trips serial ids whose deltas exceed 0x7F' do
      ids = [100, 2312, 296_002]
      encoded = codec.encode_delta_varint(Set.new(ids))
      bytes = Base64.strict_decode64(encoded).bytes
      decoded = []
      prev = 0
      shift = 0
      acc = 0
      bytes.each do |byte|
        acc |= (byte & 0x7F) << shift
        if (byte & 0x80).zero?
          prev += acc
          decoded << prev
          acc = 0
          shift = 0
        else
          shift += 7
        end
      end
      expect(decoded).to eq(ids)
    end

    it 'round-trips through delta decode' do
      encoded = codec.encode_delta_varint(Set[100, 108, 128, 130])
      bytes = Base64.strict_decode64(encoded).bytes
      # Decode ULEB128 deltas and reconstruct the absolute ids.
      ids = []
      prev = 0
      shift = 0
      acc = 0
      bytes.each do |byte|
        acc |= (byte & 0x7F) << shift
        if (byte & 0x80).zero?
          prev += acc
          ids << prev
          acc = 0
          shift = 0
        else
          shift += 7
        end
      end
      expect(ids).to eq([100, 108, 128, 130])
    end

    it 'hashes the targeting key as lowercase hex SHA256' do
      expect(codec.hash_targeting_key('user-123'))
        .to eq('fcdec6df4d44dbc637c7c5b58efface52a7f8a88535423430255be0bb89bedd8')
    end
  end

  describe Datadog::OpenFeature::Hooks::SpanEnrichmentHook::Accumulator do
    subject(:accumulator) { described_class.new }

    describe '#add_serial_id' do
      it 'accumulates and dedupes serial ids' do
        accumulator.add_serial_id(100)
        accumulator.add_serial_id(100)
        accumulator.add_serial_id(108)

        tags = accumulator.to_span_tags
        expect(tags['ffe_flags_enc']).to eq(Datadog::OpenFeature::Hooks::SpanEnrichmentHook::Codec.encode_delta_varint(Set[100, 108]))
      end

      it 'enforces the 200 serial id limit' do
        250.times { |i| accumulator.add_serial_id(i) }
        decoded = Base64.strict_decode64(accumulator.to_span_tags['ffe_flags_enc']).bytes
        # 200 single-byte deltas (all ids < 128 so one byte each, deltas of 1).
        count = decoded.count { |b| (b & 0x80).zero? }
        expect(count).to eq(200)
      end
    end

    describe '#add_subject' do
      it 'emits ffe_subjects_enc as a JSON object of {sha256hex => base64}' do
        accumulator.add_serial_id(100)
        accumulator.add_subject('user-123', 100)

        subjects = JSON.parse(accumulator.to_span_tags['ffe_subjects_enc'])
        hashed = Digest::SHA256.hexdigest('user-123')
        expect(subjects.keys).to eq([hashed])
        expect(subjects[hashed]).to eq(Datadog::OpenFeature::Hooks::SpanEnrichmentHook::Codec.encode_delta_varint(Set[100]))
      end

      it 'enforces the 10 subject limit' do
        accumulator.add_serial_id(1)
        12.times { |i| accumulator.add_subject("user-#{i}", 1) }
        subjects = JSON.parse(accumulator.to_span_tags['ffe_subjects_enc'])
        expect(subjects.size).to eq(10)
      end

      it 'enforces the 20 experiments-per-subject limit' do
        25.times { |i| accumulator.add_serial_id(i) }
        25.times { |i| accumulator.add_subject('user-123', i) }
        subjects = JSON.parse(accumulator.to_span_tags['ffe_subjects_enc'])
        hashed = Digest::SHA256.hexdigest('user-123')
        decoded = Base64.strict_decode64(subjects[hashed]).bytes
        count = decoded.count { |b| (b & 0x80).zero? }
        expect(count).to eq(20)
      end
    end

    describe '#add_default' do
      it 'emits ffe_runtime_defaults as a JSON object string' do
        accumulator.add_default('flag-a', 'control')
        defaults = JSON.parse(accumulator.to_span_tags['ffe_runtime_defaults'])
        expect(defaults).to eq('flag-a' => 'control')
      end

      it 'JSON-encodes object defaults (not [object Object]/inspect)' do
        accumulator.add_default('flag-obj', {'feature' => 'enabled', 'count' => 42})
        defaults = JSON.parse(accumulator.to_span_tags['ffe_runtime_defaults'])
        expect(JSON.parse(defaults['flag-obj'])).to eq('feature' => 'enabled', 'count' => 42)
      end

      it 'is first-wins for a repeated flag key' do
        accumulator.add_default('flag-a', 'first')
        accumulator.add_default('flag-a', 'second')
        defaults = JSON.parse(accumulator.to_span_tags['ffe_runtime_defaults'])
        expect(defaults['flag-a']).to eq('first')
      end

      it 'truncates default values longer than 64 chars' do
        accumulator.add_default('flag-a', 'x' * 100)
        defaults = JSON.parse(accumulator.to_span_tags['ffe_runtime_defaults'])
        expect(defaults['flag-a'].length).to eq(64)
      end

      it 'enforces the 5 defaults limit' do
        7.times { |i| accumulator.add_default("flag-#{i}", 'v') }
        defaults = JSON.parse(accumulator.to_span_tags['ffe_runtime_defaults'])
        expect(defaults.size).to eq(5)
      end
    end

    describe '#has_data?' do
      it 'is false when empty' do
        expect(accumulator.has_data?).to be(false)
      end

      it 'is true with serial ids' do
        accumulator.add_serial_id(1)
        expect(accumulator.has_data?).to be(true)
      end

      it 'is true with defaults' do
        accumulator.add_default('flag-a', 'v')
        expect(accumulator.has_data?).to be(true)
      end
    end

    describe '#to_span_tags' do
      it 'omits ffe_flags_enc when there are no serial ids' do
        accumulator.add_default('flag-a', 'v')
        expect(accumulator.to_span_tags).not_to have_key('ffe_flags_enc')
      end
    end
  end

  describe '#capture' do
    it 'accumulates a serial id for the active root span' do
      hook.capture(flag_key: 'flag-a', variant: 'on', value: 'on', serial_id: 100, do_log: false, targeting_key: 'user-123')

      state = accumulator_store.fetch(trace_op)
      expect(state.has_data?).to be(true)
      expect(state.to_span_tags['ffe_flags_enc']).to eq('ZA==')
    end

    it 'adds a subject only when do_log is true and a targeting key is present' do
      hook.capture(flag_key: 'flag-a', variant: 'on', value: 'on', serial_id: 100, do_log: true, targeting_key: 'user-123')

      state = accumulator_store.fetch(trace_op)
      expect(state.to_span_tags).to have_key('ffe_subjects_enc')
    end

    it 'does not add a subject when do_log is false' do
      hook.capture(flag_key: 'flag-a', variant: 'on', value: 'on', serial_id: 100, do_log: false, targeting_key: 'user-123')

      state = accumulator_store.fetch(trace_op)
      expect(state.to_span_tags).not_to have_key('ffe_subjects_enc')
    end

    it 'detects a runtime default via a missing variant' do
      hook.capture(flag_key: 'flag-default', variant: nil, value: 'control', serial_id: nil, do_log: false, targeting_key: nil)

      state = accumulator_store.fetch(trace_op)
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
      expect(accumulator_store.fetch(trace_op)).to be_nil
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
      expect(accumulator_store.fetch(trace_op)).to be_nil
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
      expect(accumulator_store.fetch(trace_op)).to be_nil
    end
  end

  describe '#shutdown' do
    it 'clears all accumulated state' do
      hook.capture(flag_key: 'flag-a', variant: 'on', value: 'on', serial_id: 100, do_log: false, targeting_key: nil)
      expect(accumulator_store.fetch(trace_op)).not_to be_nil

      hook.shutdown

      expect(accumulator_store.fetch(trace_op)).to be_nil
    end
  end
end
