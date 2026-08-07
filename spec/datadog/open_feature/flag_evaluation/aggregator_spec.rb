# frozen_string_literal: true

require "spec_helper"
require "datadog/open_feature/flag_evaluation/aggregator"

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

  def expected_context_key(*fields)
    fields.map do |key, tag, value|
      [key.bytesize].pack("Q>") + key + tag + [value.bytesize].pack("Q>") + value
    end.join
  end

  # canonical_context_key

  describe "#canonical_context_key" do
    it "returns empty string for nil attrs" do
      expect(aggregator.canonical_context_key(nil)).to eq("")
    end

    it "returns empty string for empty attrs" do
      expect(aggregator.canonical_context_key({})).to eq("")
    end

    it "encodes scalar values with explicit type tags" do
      expect(aggregator.canonical_context_key("x" => "1"))
        .to eq(expected_context_key(["x", "s", "1"]))
      expect(aggregator.canonical_context_key("x" => true))
        .to eq(expected_context_key(["x", "b", "true"]))
      expect(aggregator.canonical_context_key("x" => 1))
        .to eq(expected_context_key(["x", "i", "1"]))
      expect(aggregator.canonical_context_key("x" => 1.0))
        .to eq(expected_context_key(["x", "f", "1.0"]))
    end

    it "is deterministic for the same attrs regardless of insertion order" do
      key_ab = aggregator.canonical_context_key("a" => "v1", "b" => "v2")
      key_ba = aggregator.canonical_context_key("b" => "v2", "a" => "v1")
      expected = expected_context_key(["a", "s", "v1"], ["b", "s", "v2"])

      expect(key_ab).to eq(expected)
      expect(key_ba).to eq(expected)
    end

    it "uses sorted type-tagged triplets (canonical key contains key and value lengths)" do
      key = aggregator.canonical_context_key("env" => "prod")
      expected = expected_context_key(["env", "s", "prod"])

      expect(key).to eq(expected)
    end

    it "length-delimits keys and values with embedded separators" do
      expect(aggregator.canonical_context_key("a=b" => "c"))
        .to eq(expected_context_key(["a=b", "s", "c"]))
      expect(aggregator.canonical_context_key("a" => "b=c"))
        .to eq(expected_context_key(["a", "s", "b=c"]))
    end
  end

  # context pruning

  describe "#prune_context" do
    it "skips string values exceeding 256 chars" do
      long_value = "x" * 257
      attrs = {"key" => long_value, "other" => "fine"}
      pruned = aggregator.prune_context(attrs)
      expect(pruned.keys).not_to include("key")
      expect(pruned.keys).to include("other")
    end

    it "flattens nested hashes and arrays with dot-notation keys" do
      attrs = {"profile" => {"plan" => "pro"}, "groups" => ["beta", "staff"]}
      pruned = aggregator.prune_context(attrs)
      expect(pruned).to include("profile.plan" => "pro", "groups.0" => "beta", "groups.1" => "staff")
    end

    it "omits nil values and keeps empty string values" do
      attrs = {"profile" => {"plan" => "pro", "" => 1, "what" => ""}, "groups" => ["beta", "staff", nil, ""]}
      pruned = aggregator.prune_context(attrs)

      expect(pruned).to include(
        "groups.0" => "beta",
        "groups.1" => "staff",
        "groups.3" => "",
        "profile." => 1,
        "profile.plan" => "pro",
        "profile.what" => "",
      )
      expect(pruned).not_to have_key("groups.2")
    end

    it "keeps string values of exactly 256 chars" do
      exact_value = "x" * 256
      attrs = {"key" => exact_value}
      pruned = aggregator.prune_context(attrs)
      expect(pruned.keys).to include("key")
    end

    it "caps at 256 fields" do
      attrs = 257.times.each_with_object({}) { |i, h| h["k#{i}"] = "v" }
      pruned = aggregator.prune_context(attrs)
      expect(pruned.size).to eq(256)
    end

    it "drops keys after the sorted 256-field cap" do
      attrs = 257.times.each_with_object({}) { |i, h| h["k#{format("%03d", i)}"] = "v" }
      pruned = aggregator.prune_context(attrs)
      expected_keys = 256.times.map { |i| "k#{format("%03d", i)}" }

      expect(pruned.keys).to eq(expected_keys)
      expect(pruned).not_to have_key("k256")
    end

    it "returns empty hash for nil input" do
      expect(aggregator.prune_context(nil)).to eq({})
    end

    it "does not recurse forever on cyclic hashes and arrays" do
      attrs = {"keep" => "ok"}
      attrs["self"] = attrs
      attrs["array"] = []
      attrs["array"] << attrs["array"]

      pruned = aggregator.prune_context(attrs)

      expect(pruned).to include("keep" => "ok")
      expect(pruned.keys.grep(/self|array/)).to be_empty
    end

    it "drops context branches beyond the maximum nesting depth" do
      attrs = {"root" => {}}
      cursor = attrs["root"]
      (described_class::MAX_CONTEXT_DEPTH + 2).times do |i|
        cursor["level#{i}"] = {}
        cursor = cursor["level#{i}"]
      end
      cursor["leaf"] = "too-deep"

      expect(aggregator.prune_context(attrs)).to eq({})
    end
  end

  # record + two-tier aggregation

  describe "#record" do
    let(:base_event) do
      {
        flag_key: "my-flag",
        variant: "on",
        allocation_key: "alloc-1",
        targeting_key: "user-123",
        eval_time_ms: 1_700_000_000_000,
        attrs: {"env" => "prod"},
      }
    end

    context "two identical evaluations" do
      it "creates one full-tier bucket with count 2 and min/max first/last" do
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
      it "creates two distinct full-tier buckets (type-tagged canonical key)" do
        aggregator.record(**base_event.merge(attrs: {"x" => 1}))
        aggregator.record(**base_event.merge(attrs: {"x" => "1"}))

        snapshot = aggregator.flush_and_reset
        expect(snapshot[:full].size).to eq(2)
      end
    end

    context "runtime_default detection" do
      it "marks runtime_default_used true when variant is nil" do
        aggregator.record(**base_event.merge(variant: nil))

        snapshot = aggregator.flush_and_reset
        entry = snapshot[:full].values.first
        expect(entry[:runtime_default]).to be(true)
      end

      it "does not mark runtime_default_used when variant is present" do
        aggregator.record(**base_event)

        snapshot = aggregator.flush_and_reset
        entry = snapshot[:full].values.first
        expect(entry[:runtime_default]).to be(false)
      end

      it "uses an explicit runtime_default signal when the SDK returns a typed default" do
        aggregator.record(**base_event.merge(runtime_default: true))

        snapshot = aggregator.flush_and_reset
        entry = snapshot[:full].values.first
        expect(entry[:runtime_default]).to be(true)
      end
    end

    context "full-tier global_cap overflow routes to degraded" do
      let(:global_cap) { 2 }
      let(:per_flag_cap) { 10 }

      it "routes to degraded when global_cap is reached with a new bucket" do
        # First two fill the full tier
        aggregator.record(**base_event.merge(attrs: {"x" => 1}))
        aggregator.record(**base_event.merge(attrs: {"x" => 2}))
        # Third has different context — full tier full — routes to degraded
        aggregator.record(**base_event.merge(attrs: {"x" => 3}))

        snapshot = aggregator.flush_and_reset
        expect(snapshot[:full].size).to eq(2)
        expect(snapshot[:degraded].size).to eq(1)
      end

      it "counts full-tier attempts before global cap routing" do
        aggregator.record(**base_event.merge(attrs: {"x" => 1}))
        aggregator.record(**base_event.merge(attrs: {"x" => 2}))
        aggregator.record(**base_event.merge(attrs: {"x" => 3}))

        per_flag_full = aggregator.instance_variable_get(:@per_flag_full)
        expect(per_flag_full["my-flag"]).to eq(3)
      end
    end

    context "full-tier per_flag_cap overflow routes to degraded" do
      let(:global_cap) { 131_072 }
      let(:per_flag_cap) { 2 }

      it "routes to degraded when per_flag_cap is reached for a flag" do
        aggregator.record(**base_event.merge(attrs: {"x" => 1}))
        aggregator.record(**base_event.merge(attrs: {"x" => 2}))
        # Third bucket for same flag: per_flag_cap exceeded
        aggregator.record(**base_event.merge(attrs: {"x" => 3}))

        snapshot = aggregator.flush_and_reset
        expect(snapshot[:full].size).to eq(2)
        expect(snapshot[:degraded].size).to eq(1)
      end
    end

    context "degraded-tier degraded_cap overflow increments dropped counter" do
      let(:global_cap) { 1 }    # force overflow to degraded immediately
      let(:per_flag_cap) { 1 }
      let(:degraded_cap) { 1 }  # then degrade overflows

      it "increments dropped counter beyond degraded_cap" do
        # First event: goes to full tier (cap=1, one slot)
        aggregator.record(**base_event.merge(attrs: {"x" => 1}))
        # Second event: different context, full tier full → goes to degraded.
        # creates the one allowed degraded bucket
        aggregator.record(**base_event.merge(attrs: {"x" => 2}))
        # Third event: different schema-visible error.message → degraded full → DROPPED
        aggregator.record(**base_event.merge(attrs: {"x" => 3}, error_message: "boom"))

        expect(aggregator.dropped_degraded_overflow).to eq(1)
      end
    end

    context "degraded tier omits targeting_key and context (omitempty schema fields)" do
      let(:global_cap) { 1 }
      let(:per_flag_cap) { 1 }

      it "degraded entry has no targeting_key or context_attrs" do
        aggregator.record(**base_event.merge(attrs: {"x" => 1}))
        # Force overflow to degraded
        aggregator.record(**base_event.merge(attrs: {"x" => 2}))

        snapshot = aggregator.flush_and_reset
        degraded_entry = snapshot[:degraded].values.first
        expect(degraded_entry[:targeting_key]).to be_nil
        expect(degraded_entry[:context_attrs]).to be_nil
      end
    end
  end

  # flush_and_reset

  describe "#flush_and_reset" do
    it "resets full and degraded maps after flush" do
      aggregator.record(
        flag_key: "f", variant: "v", allocation_key: "",
        targeting_key: "", eval_time_ms: 1000, attrs: {}
      )
      aggregator.flush_and_reset
      snapshot2 = aggregator.flush_and_reset
      expect(snapshot2[:full]).to be_empty
      expect(snapshot2[:degraded]).to be_empty
    end

    it "resets dropped_degraded_overflow counter after flush" do
      aggregator_small = described_class.new(global_cap: 1, per_flag_cap: 1, degraded_cap: 1)
      aggregator_small.record(flag_key: "f", variant: "v", allocation_key: "", targeting_key: "", eval_time_ms: 1, attrs: {"x" => 1})
      aggregator_small.record(flag_key: "f", variant: "v", allocation_key: "", targeting_key: "", eval_time_ms: 2, attrs: {"x" => 2})
      aggregator_small.record(flag_key: "f", variant: "v", allocation_key: "", targeting_key: "", eval_time_ms: 3, attrs: {"x" => 3})
      aggregator_small.flush_and_reset
      expect(aggregator_small.dropped_degraded_overflow).to eq(0)
    end

    # The snapshot must CARRY the degraded-overflow count so the writer can emit it before
    # reset (not reset-without-emit). The count must equal what dropped at flush time.
    it "returns the degraded-overflow count in the snapshot so it can be emitted before reset" do
      aggregator_small = described_class.new(global_cap: 1, per_flag_cap: 1, degraded_cap: 1)
      aggregator_small.record(flag_key: "f", variant: "v", allocation_key: "", targeting_key: "", eval_time_ms: 1, attrs: {"x" => 1})
      aggregator_small.record(flag_key: "f", variant: "v", allocation_key: "", targeting_key: "", eval_time_ms: 2, attrs: {"x" => 2})
      aggregator_small.record(
        flag_key: "f", variant: "v", allocation_key: "", error_message: "boom",
        targeting_key: "", eval_time_ms: 3, attrs: {"x" => 3}
      )

      snapshot = aggregator_small.flush_and_reset
      expect(snapshot[:dropped_degraded_overflow]).to be >= 1
      # And after flush the internal counter is reset (single source of truth).
      expect(aggregator_small.dropped_degraded_overflow).to eq(0)
    end
  end
end
