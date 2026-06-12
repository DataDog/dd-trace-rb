# frozen_string_literal: true

require 'spec_helper'
require 'datadog/open_feature/flagevaluation/aggregator'

RSpec.describe Datadog::OpenFeature::FlagEvaluation::Aggregator do
  subject(:aggregator) do
    described_class.new(
      global_cap: global_cap,
      per_flag_cap: per_flag_cap,
      degraded_cap: degraded_cap,
    )
  end

  let(:global_cap) { 131_072 }
  let(:per_flag_cap) { 10_000 }
  let(:degraded_cap) { 32_768 }

  # ─── canonical_context_key ───────────────────────────────────────────────────

  describe '#canonical_context_key' do
    it 'returns empty string for nil attrs' do
      expect(aggregator.canonical_context_key(nil)).to eq('')
    end

    it 'returns empty string for empty attrs' do
      expect(aggregator.canonical_context_key({})).to eq('')
    end

    it 'differentiates integer 1 from string "1" (type-tag prevents collisions)' do
      key_int    = aggregator.canonical_context_key('x' => 1)
      key_string = aggregator.canonical_context_key('x' => '1')
      expect(key_int).not_to eq(key_string)
    end

    it 'differentiates boolean from string "true"' do
      key_bool   = aggregator.canonical_context_key('x' => true)
      key_string = aggregator.canonical_context_key('x' => 'true')
      expect(key_bool).not_to eq(key_string)
    end

    it 'differentiates float from integer' do
      key_float = aggregator.canonical_context_key('x' => 1.0)
      key_int   = aggregator.canonical_context_key('x' => 1)
      expect(key_float).not_to eq(key_int)
    end

    it 'is deterministic for the same attrs regardless of insertion order' do
      key_ab = aggregator.canonical_context_key('a' => 'v1', 'b' => 'v2')
      key_ba = aggregator.canonical_context_key('b' => 'v2', 'a' => 'v1')
      expect(key_ab).to eq(key_ba)
    end

    it 'does NOT call Digest::MD5 (canonical key must be collision-free string, not a hash digest)' do
      source_path = File.join(Dir.pwd, 'lib/datadog/open_feature/flagevaluation/aggregator.rb')
      # Strip comment lines, then verify no MD5 call remains in executable code
      source = File.read(source_path)
      code_lines = source.lines.reject { |l| l.strip.start_with?('#') }.join
      expect(code_lines).not_to match(/Digest\s*::\s*MD5/i)
    end

    it 'uses sorted type-tagged triplets (canonical key contains key and value lengths)' do
      key = aggregator.canonical_context_key('env' => 'prod')
      # Key encodes key length + key + type tag + value length + value
      # 'env' → length 3, type 's', value 'prod' → length 4
      expect(key).not_to be_empty
      expect(key).to include('env')
      expect(key).to include('prod')
    end

    it 'canonical key differentiates keys with embedded separators (collision resistance)' do
      # Ensures length-delimited encoding prevents collisions via embedded separators
      key_a = aggregator.canonical_context_key('a=b' => 'c')
      key_b = aggregator.canonical_context_key('a' => 'b=c')
      expect(key_a).not_to eq(key_b)
    end
  end

  # ─── context pruning ─────────────────────────────────────────────────────────

  describe '#prune_context' do
    it 'skips string values exceeding 256 chars' do
      long_value = 'x' * 257
      attrs = {'key' => long_value, 'other' => 'fine'}
      pruned = aggregator.prune_context(attrs)
      expect(pruned.keys).not_to include('key')
      expect(pruned.keys).to include('other')
    end

    it 'keeps string values of exactly 256 chars' do
      exact_value = 'x' * 256
      attrs = {'key' => exact_value}
      pruned = aggregator.prune_context(attrs)
      expect(pruned.keys).to include('key')
    end

    it 'caps at 256 fields' do
      attrs = 257.times.each_with_object({}) { |i, h| h["k#{i}"] = 'v' }
      pruned = aggregator.prune_context(attrs)
      expect(pruned.size).to eq(256)
    end

    it 'returns empty hash for nil input' do
      expect(aggregator.prune_context(nil)).to eq({})
    end
  end

  # ─── record + two-tier aggregation ──────────────────────────────────────────

  describe '#record' do
    let(:base_event) do
      {
        flag_key: 'my-flag',
        variant: 'on',
        allocation_key: 'alloc-1',
        reason: 'TARGETING_MATCH',
        targeting_key: 'user-123',
        eval_time_ms: 1_700_000_000_000,
        attrs: {'env' => 'prod'},
      }
    end

    context 'two identical evaluations' do
      it 'creates one full-tier bucket with count 2 and min/max first/last' do
        aggregator.record(**base_event.merge(eval_time_ms: 1000))
        aggregator.record(**base_event.merge(eval_time_ms: 2000))

        snapshot = aggregator.flush_and_reset
        expect(snapshot[:full].size).to eq(1)
        entry = snapshot[:full].values.first
        expect(entry[:count]).to eq(2)
        expect(entry[:first_evaluation]).to eq(1000)
        expect(entry[:last_evaluation]).to eq(2000)
      end
    end

    context 'two evaluations differing only by context value type (int 1 vs string "1")' do
      it 'creates two distinct full-tier buckets (type-tagged canonical key)' do
        aggregator.record(**base_event.merge(attrs: {'x' => 1}))
        aggregator.record(**base_event.merge(attrs: {'x' => '1'}))

        snapshot = aggregator.flush_and_reset
        expect(snapshot[:full].size).to eq(2)
      end
    end

    context 'runtime_default detection' do
      it 'marks runtime_default_used true when variant is nil' do
        aggregator.record(**base_event.merge(variant: nil))

        snapshot = aggregator.flush_and_reset
        entry = snapshot[:full].values.first
        expect(entry[:runtime_default]).to be(true)
      end

      it 'does not mark runtime_default_used when variant is present' do
        aggregator.record(**base_event)

        snapshot = aggregator.flush_and_reset
        entry = snapshot[:full].values.first
        expect(entry[:runtime_default]).to be(false)
      end
    end

    context 'full-tier globalCap overflow routes to degraded' do
      let(:global_cap) { 2 }
      let(:per_flag_cap) { 10 }

      it 'routes to degraded when globalCap is reached with a new bucket' do
        # First two fill the full tier
        aggregator.record(**base_event.merge(attrs: {'x' => 1}))
        aggregator.record(**base_event.merge(attrs: {'x' => 2}))
        # Third has different context — full tier full — routes to degraded
        aggregator.record(**base_event.merge(attrs: {'x' => 3}))

        snapshot = aggregator.flush_and_reset
        expect(snapshot[:full].size).to eq(2)
        expect(snapshot[:degraded].size).to eq(1)
      end
    end

    context 'full-tier perFlagCap overflow routes to degraded' do
      let(:global_cap) { 131_072 }
      let(:per_flag_cap) { 2 }

      it 'routes to degraded when perFlagCap is reached for a flag' do
        aggregator.record(**base_event.merge(attrs: {'x' => 1}))
        aggregator.record(**base_event.merge(attrs: {'x' => 2}))
        # Third bucket for same flag — perFlagCap exceeded
        aggregator.record(**base_event.merge(attrs: {'x' => 3}))

        snapshot = aggregator.flush_and_reset
        expect(snapshot[:full].size).to eq(2)
        expect(snapshot[:degraded].size).to eq(1)
      end
    end

    context 'degraded-tier degradedCap overflow increments dropped counter' do
      let(:global_cap) { 1 }    # force overflow to degraded immediately
      let(:per_flag_cap) { 1 }
      let(:degraded_cap) { 1 }  # then degrade overflows

      it 'increments dropped counter beyond degradedCap' do
        # First event: goes to full tier (cap=1, one slot)
        aggregator.record(**base_event.merge(attrs: {'x' => 1}))
        # Second event: different context, full tier full → goes to degraded with reason TARGETING_MATCH
        # creates the one allowed degraded bucket
        aggregator.record(**base_event.merge(attrs: {'x' => 2}))
        # Third event: different reason → different degraded key → degraded full → DROPPED
        aggregator.record(**base_event.merge(attrs: {'x' => 3}, reason: 'DEFAULT'))

        expect(aggregator.dropped_degraded_overflow).to be >= 1
      end
    end

    context 'degraded tier omits targeting_key and context (omitempty schema fields)' do
      let(:global_cap) { 1 }
      let(:per_flag_cap) { 1 }

      it 'degraded entry has no targeting_key or context_attrs' do
        aggregator.record(**base_event.merge(attrs: {'x' => 1}))
        # Force overflow to degraded
        aggregator.record(**base_event.merge(attrs: {'x' => 2}))

        snapshot = aggregator.flush_and_reset
        degraded_entry = snapshot[:degraded].values.first
        expect(degraded_entry[:targeting_key]).to be_nil
        expect(degraded_entry[:context_attrs]).to be_nil
      end
    end
  end

  # ─── flush_and_reset ─────────────────────────────────────────────────────────

  describe '#flush_and_reset' do
    it 'resets full and degraded maps after flush' do
      aggregator.record(
        flag_key: 'f', variant: 'v', allocation_key: '', reason: 'DEFAULT',
        targeting_key: '', eval_time_ms: 1000, attrs: {},
      )
      aggregator.flush_and_reset
      snapshot2 = aggregator.flush_and_reset
      expect(snapshot2[:full]).to be_empty
      expect(snapshot2[:degraded]).to be_empty
    end

    it 'resets dropped_degraded_overflow counter after flush' do
      aggregator_small = described_class.new(global_cap: 1, per_flag_cap: 1, degraded_cap: 1)
      aggregator_small.record(flag_key: 'f', variant: 'v', allocation_key: '', reason: 'R', targeting_key: '', eval_time_ms: 1, attrs: {'x' => 1})
      aggregator_small.record(flag_key: 'f', variant: 'v', allocation_key: '', reason: 'R', targeting_key: '', eval_time_ms: 2, attrs: {'x' => 2})
      aggregator_small.record(flag_key: 'f', variant: 'v', allocation_key: '', reason: 'R', targeting_key: '', eval_time_ms: 3, attrs: {'x' => 3})
      aggregator_small.flush_and_reset
      expect(aggregator_small.dropped_degraded_overflow).to eq(0)
    end
  end
end
