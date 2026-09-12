require "spec_helper"
require "datadog/di/snapshot_pruner"
require "json"

RSpec.describe Datadog::DI::SnapshotPruner do
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
          probe: {
            id: "p1",
            version: 0,
            location: {file: "app.rb", lines: ["42"]},
          },
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
    return true if value.is_a?(Hash) && value["pruned"] == true
    return value.values.any? { |v| contains_pruned?(v) } if value.is_a?(Hash)
    return value.any? { |v| contains_pruned?(v) } if value.is_a?(Array)
    false
  end

  describe ".prune" do
    let(:cap) { 1024 * 1024 }
    let(:snapshot) { build_snapshot(captures) }

    def prune
      described_class.prune(snapshot, cap, encoded: JSON.dump(snapshot))
    end

    context "when the snapshot is already under the cap" do
      let(:captures) { {lines: {42 => {locals: {x: {type: "Integer", value: "1"}}}}} }

      it "returns the encoded json unchanged" do
        encoded = prune
        expect(encoded).to eq(JSON.dump(snapshot))
        expect(encoded.bytesize).to be <= cap
      end
    end

    context "when a single captured string exceeds the cap" do
      let(:captures) do
        {lines: {42 => {
          locals: {
            big: {type: "String", value: "x" * (cap + 10)},
            small: {type: "Integer", value: "1"},
          },
          arguments: {self: {type: "String", value: "self"}},
        }}}
      end

      before do
        expect(JSON.dump(snapshot).bytesize).to be > cap
      end

      it "prunes the oversized value and fits under the cap" do
        pruned = prune
        expect(pruned).not_to be_nil
        expect(pruned.bytesize).to be <= cap
        expect(pruned.bytesize).to be < JSON.dump(snapshot).bytesize
        expect(contains_pruned?(parsed_captures(pruned))).to be(true)
      end
    end

    context "when a large collection of many small items exceeds the cap" do
      let(:elements) { Array.new(40_000) { |i| {type: "Integer", value: i.to_s} } }
      let(:captures) do
        {lines: {42 => {
          locals: {
            largeCollection: {type: "Array", elements: elements},
            small: {type: "Integer", value: "1"},
          },
          arguments: {self: {type: "String", value: "self"}},
        }}}
      end

      before do
        expect(JSON.dump(snapshot).bytesize).to be > cap
      end

      it "prunes the collection as one unit" do
        pruned = prune
        expect(pruned).not_to be_nil
        expect(pruned.bytesize).to be <= cap
        expect(contains_pruned?(parsed_captures(pruned))).to be(true)
      end
    end

    context "when multiple captured variables exceed the cap" do
      let(:captures) do
        {lines: {42 => {
          locals: {
            a: {type: "String", value: "y" * (cap / 2 + 1000)},
            b: {type: "String", value: "z" * (cap / 2 + 1000)},
            c: {type: "Integer", value: "1"},
          },
          arguments: {self: {type: "String", value: "self"}},
        }}}
      end

      before do
        expect(JSON.dump(snapshot).bytesize).to be > cap
      end

      it "prunes variables until the cap is met" do
        pruned = prune
        expect(pruned).not_to be_nil
        expect(pruned.bytesize).to be <= cap
        expect(contains_pruned?(parsed_captures(pruned))).to be(true)
      end
    end

    context "when an oversized captured string is pruned" do
      let(:captures) do
        {lines: {42 => {
          locals: {big: {type: "String", value: "x" * (cap + 10)}},
          arguments: {self: {type: "String", value: "self"}},
        }}}
      end

      before do
        expect(JSON.dump(snapshot).bytesize).to be > cap
      end

      it "preserves the structural envelope (probe, stack)" do
        pruned = prune
        parsed = JSON.parse(pruned)
        expect(parsed.dig("debugger", "snapshot", "probe")).to include("id" => "p1")
        expect(parsed.dig("debugger", "snapshot", "stack")).to be_an(Array)
      end

      it "does not mutate the input snapshot" do
        before_snapshot = Marshal.load(Marshal.dump(snapshot))
        prune
        expect(snapshot).to eq(before_snapshot)
      end
    end

    context "when a throwable capture exceeds the cap" do
      let(:captures) do
        {lines: {42 => {
          locals: {small: {type: "Integer", value: "1"}},
          throwable: {type: "RuntimeError", message: "x" * (cap + 10)},
        }}}
      end

      before do
        expect(JSON.dump(snapshot).bytesize).to be > cap
      end

      it "prunes the throwable value" do
        pruned = prune
        expect(pruned).not_to be_nil
        expect(pruned.bytesize).to be <= cap
        expect(contains_pruned?(parsed_captures(pruned))).to be(true)
      end
    end

    context "when capture expression values exceed the cap" do
      let(:captures) do
        {lines: {42 => {
          captureExpressions: {
            big: {type: "String", value: "x" * (cap + 10)},
            small: {type: "Integer", value: "1"},
          },
        }}}
      end

      before do
        expect(JSON.dump(snapshot).bytesize).to be > cap
      end

      it "prunes the oversized capture expression value" do
        pruned = prune
        expect(pruned).not_to be_nil
        expect(pruned.bytesize).to be <= cap
        expect(contains_pruned?(parsed_captures(pruned))).to be(true)
      end
    end

    context "when a multibyte UTF-8 value exceeds the cap" do
      let(:captures) do
        {lines: {42 => {
          locals: {big: {type: "String", value: "\u00e9" * (cap / 2 + 100)}},
          arguments: {self: {type: "String", value: "self"}},
        }}}
      end

      before do
        expect(JSON.dump(snapshot).bytesize).to be > cap
      end

      it "prunes correctly using byte-size measurement" do
        pruned = prune
        expect(pruned).not_to be_nil
        expect(pruned.bytesize).to be <= cap
        expect { JSON.parse(pruned) }.not_to raise_error
        expect(contains_pruned?(parsed_captures(pruned))).to be(true)
      end
    end

    context "when individual pruning cannot fit but collapsing captures can" do
      # The envelope is large enough that pruning the small captured values
      # alone cannot reach the cap, but collapsing all captures to the
      # pruned marker does fit, so the snapshot envelope is still delivered.
      let(:cap) { 680 }
      let(:snapshot) do
        build_snapshot({
          lines: {42 => {
            locals: {
              a: {type: "String", value: "a" * 80},
              b: {type: "String", value: "b" * 80},
            },
          }},
        }).tap do |s|
          s[:debugger][:snapshot][:stack] = [
            {fileName: "s" * 300, function: "test", lineNumber: 42},
          ]
        end
      end

      it "delivers the envelope with captures collapsed to the pruned marker" do
        pruned = described_class.prune(snapshot, cap, encoded: JSON.dump(snapshot))
        expect(pruned).not_to be_nil
        expect(pruned.bytesize).to be <= cap
        parsed = JSON.parse(pruned)
        expect(parsed.dig("debugger", "snapshot", "captures")).to eq("pruned" => true)
      end
    end

    context "when no captured values can be pruned" do
      let(:snapshot) do
        build_snapshot({}).tap do |s|
          s[:debugger][:snapshot][:stack] = [
            {fileName: "x" * (1024 * 1024 + 10), function: "test", lineNumber: 42},
          ]
        end
      end

      before do
        expect(JSON.dump(snapshot).bytesize).to be > 1024 * 1024
      end

      it "returns nil when the envelope alone exceeds the cap" do
        expect(described_class.prune(snapshot, 1024 * 1024, encoded: JSON.dump(snapshot))).to be_nil
      end
    end

    context "when prunable entries exist but the envelope alone still exceeds the cap" do
      let(:snapshot) do
        build_snapshot({
          lines: {42 => {locals: {small: {type: "Integer", value: "1"}}}},
        }).tap do |s|
          s[:debugger][:snapshot][:stack] = [
            {fileName: "x" * (1024 * 1024 + 10), function: "test", lineNumber: 42},
          ]
        end
      end

      before do
        expect(JSON.dump(snapshot).bytesize).to be > 1024 * 1024
      end

      it "returns nil after attempting to prune" do
        expect(described_class.prune(snapshot, 1024 * 1024, encoded: JSON.dump(snapshot))).to be_nil
      end
    end
  end
end
