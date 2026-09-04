require "spec_helper"
require "datadog/di/snapshot_pruner"
require "json"

RSpec.describe Datadog::DI::SnapshotPruner do
  # rubocop:disable Lint/ConstantDefinitionInBlock
  CAP = 1024 * 1024
  # rubocop:enable Lint/ConstantDefinitionInBlock

  # Build a snapshot Hash in the shape ProbeNotificationBuilder produces.
  # Captures is the inner captures subtree; the envelope (service,
  # debugger.snapshot.probe, stack) is fixed so prunable leaves land
  # under captures only.
  def build_snapshot(captures)
    {
      service: "svc",
      debugger: {
        type: "snapshot",
        snapshot: {
          id: "p1",
          timestamp: 1,
          evaluationErrors: [],
          probe: {id: "p1", version: 0,
                  location: {file: "app.rb", lines: ["42"]}},
          language: "ruby",
          stack: [{fileName: "app.rb", function: "test", lineNumber: 42}],
          captures: captures,
        },
      },
      duration: 0,
      ddsource: "dd_debugger",
      message: nil,
      timestamp: 1,
    }
  end

  def parsed_captures(encoded)
    JSON.parse(encoded).dig("debugger", "snapshot", "captures")
  end

  def contains_pruned?(value)
    return true if value.is_a?(Hash) && (value["pruned"] == true ||
      value["notCapturedReason"] == "payloadTooLarge")
    return value.values.any? { |v| contains_pruned?(v) } if value.is_a?(Hash)
    return value.any? { |v| contains_pruned?(v) } if value.is_a?(Array)
    false
  end

  describe ".prune" do
    it "returns the encoded json unchanged when already under the cap" do
      captures = {lines: {42 => {locals: {x: {type: "Integer", value: "1"}}}}}
      snapshot = build_snapshot(captures)
      encoded = described_class.prune(snapshot, CAP, encoded: JSON.dump(snapshot))
      expect(encoded).to eq(JSON.dump(snapshot))
      expect(encoded.bytesize).to be <= CAP
    end

    it "prunes a single oversized captured string and fits under the cap" do
      big = "x" * (CAP + 10)
      captures = {lines: {42 => {
        locals: {big: {type: "String", value: big},
                 small: {type: "Integer", value: "1"}},
        arguments: {self: {type: "String", value: "self"}},
      }}}
      snapshot = build_snapshot(captures)

      pruned = described_class.prune(snapshot, CAP, encoded: JSON.dump(snapshot))
      expect(pruned).not_to be_nil
      expect(pruned.bytesize).to be <= CAP
      expect(pruned.bytesize).to be < JSON.dump(snapshot).bytesize
      expect(contains_pruned?(parsed_captures(pruned))).to be(true)
    end

    it "prunes a large collection of many small items as one unit" do
      elements = Array.new(40_000) { |i| {type: "Integer", value: i.to_s} }
      captures = {lines: {42 => {
        locals: {largeCollection: {type: "Array", elements: elements},
                 small: {type: "Integer", value: "1"}},
        arguments: {self: {type: "String", value: "self"}},
      }}}
      snapshot = build_snapshot(captures)
      expect(JSON.dump(snapshot).bytesize).to be > CAP

      pruned = described_class.prune(snapshot, CAP, encoded: JSON.dump(snapshot))
      expect(pruned).not_to be_nil
      expect(pruned.bytesize).to be <= CAP
      expect(contains_pruned?(parsed_captures(pruned))).to be(true)
    end

    it "prunes multiple oversized variables until the cap is met" do
      big1 = "y" * (CAP / 2 + 1000)
      big2 = "z" * (CAP / 2 + 1000)
      captures = {lines: {42 => {
        locals: {
          a: {type: "String", value: big1},
          b: {type: "String", value: big2},
          c: {type: "Integer", value: "1"},
        },
        arguments: {self: {type: "String", value: "self"}},
      }}}
      snapshot = build_snapshot(captures)
      expect(JSON.dump(snapshot).bytesize).to be > CAP

      pruned = described_class.prune(snapshot, CAP, encoded: JSON.dump(snapshot))
      expect(pruned).not_to be_nil
      expect(pruned.bytesize).to be <= CAP
      expect(contains_pruned?(parsed_captures(pruned))).to be(true)
    end

    it "preserves the structural envelope (probe, stack) while pruning" do
      big = "x" * (CAP + 10)
      captures = {lines: {42 => {
        locals: {big: {type: "String", value: big}},
        arguments: {self: {type: "String", value: "self"}},
      }}}
      snapshot = build_snapshot(captures)

      pruned = described_class.prune(snapshot, CAP, encoded: JSON.dump(snapshot))
      parsed = JSON.parse(pruned)
      expect(parsed.dig("debugger", "snapshot", "probe")).to include("id" => "p1")
      expect(parsed.dig("debugger", "snapshot", "stack")).to be_an(Array)
    end

    it "does not mutate the input snapshot" do
      big = "x" * (CAP + 10)
      captures = {lines: {42 => {
        locals: {big: {type: "String", value: big}},
        arguments: {self: {type: "String", value: "self"}},
      }}}
      snapshot = build_snapshot(captures)
      before = Marshal.load(Marshal.dump(snapshot))

      described_class.prune(snapshot, CAP, encoded: JSON.dump(snapshot))
      expect(snapshot).to eq(before)
    end

    it "returns nil when no captured values can be pruned" do
      # Empty captures but an oversized envelope (giant stack frame) —
      # there is nothing under captures to prune, so the snapshot cannot
      # be reduced and is dropped.
      giant_stack = [{fileName: "x" * (CAP + 10), function: "test", lineNumber: 42}]
      snapshot = build_snapshot({})
      snapshot[:debugger][:snapshot][:stack] = giant_stack
      expect(JSON.dump(snapshot).bytesize).to be > CAP

      expect(described_class.prune(snapshot, CAP, encoded: JSON.dump(snapshot))).to be_nil
    end

    it "prunes a UTF-8 snapshot with multibyte values correctly" do
      # A multibyte value (é) proves byte-size measurement is correct.
      big = "é" * (CAP / 2 + 100)
      captures = {lines: {42 => {
        locals: {big: {type: "String", value: big}},
        arguments: {self: {type: "String", value: "self"}},
      }}}
      snapshot = build_snapshot(captures)
      expect(JSON.dump(snapshot).bytesize).to be > CAP

      pruned = described_class.prune(snapshot, CAP, encoded: JSON.dump(snapshot))
      expect(pruned).not_to be_nil
      expect(pruned.bytesize).to be <= CAP
      expect { JSON.parse(pruned) }.not_to raise_error
      expect(contains_pruned?(parsed_captures(pruned))).to be(true)
    end
  end
end
