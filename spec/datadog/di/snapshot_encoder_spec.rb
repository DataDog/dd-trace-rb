require "spec_helper"
require "datadog/di/snapshot_encoder"
require "json"

RSpec.describe Datadog::DI::SnapshotEncoder do
  let(:cap) { 1024 * 1024 }

  # Build a snapshot Hash in the shape ProbeNotificationBuilder produces,
  # via assignments to avoid Ruby's nested-hash-literal parser quirk.
  def snapshot(captures)
    probe = {id: "p1", version: 0}
    probe[:location] = {file: "app.rb", lines: ["42"]}
    snap = {id: "x", timestamp: 1, evaluationErrors: [], probe: probe, language: "ruby"}
    snap[:stack] = [{fileName: "app.rb", function: "test", lineNumber: 42}]
    snap[:captures] = captures
    debugger = {type: "snapshot", snapshot: snap}
    {service: "svc", debugger: debugger, duration: 0, host: nil,
      logger: {name: "app.rb", method: "test", thread_name: "main"}}
  end

  def line_captures(locals)
    inner = {locals: locals, arguments: {self: {type: "String", value: "self"}}}
    {lines: {42 => inner}}
  end

  describe ".encode" do
    context "when the snapshot is under the cap" do
      let(:small) { snapshot(line_captures(x: {type: "Integer", value: "5"})) }

      it "encodes the snapshot unchanged with no pruning" do
        result = described_class.encode(small, cap)
        expect(result.encoded).to eq(JSON.dump(small))
        expect(result.pruned).to be(false)
      end
    end

    context "when a single captured integer exceeds the cap" do
      let(:big) { snapshot(line_captures(big: {type: "Integer", value: "1"}, small: {type: "Integer", value: "1"})) }

      before do
        big.dig(:debugger, :snapshot, :captures, :lines, 42, :locals, :big)[:value] = "9" * 500_000
      end

      it "prunes the oversized slot to the marker without encoding the value" do
        result = described_class.encode(big, cap)
        expect(result.pruned).to be(true)
        expect(result.encoded.bytesize).to be <= cap
        parsed = JSON.parse(result.encoded)
        locals = parsed.dig("debugger", "snapshot", "captures", "lines", "42", "locals")
        expect(locals["big"]).to eq("pruned" => true)
        expect(locals["small"]).to eq("type" => "Integer", "value" => "1")
        expect(result.encoded).not_to include("9" * 1000)
      end
    end

    context "when a single captured string exceeds the cap" do
      let(:bigstr) { snapshot(line_captures(s: {type: "String", value: "x"})) }

      before do
        bigstr.dig(:debugger, :snapshot, :captures, :lines, 42, :locals, :s)[:value] = "x" * 500_000
      end

      it "prunes the oversized string slot to the marker" do
        result = described_class.encode(bigstr, cap)
        expect(result.pruned).to be(true)
        expect(result.encoded.bytesize).to be <= cap
        parsed = JSON.parse(result.encoded)
        expect(parsed.dig("debugger", "snapshot", "captures", "lines", "42", "locals", "s")).to eq("pruned" => true)
      end
    end

    context "when a collection slot's lower bound exceeds the budget" do
      let(:big_collection) do
        snapshot(line_captures(items: {type: "Array", elements: Array.new(10) { {type: "Integer", value: "1"} }}))
      end

      it "prunes the whole collection slot without encoding its items" do
        result = described_class.encode(big_collection, 2_000)
        expect(result.pruned).to be(true)
        expect(result.encoded.bytesize).to be <= 2_000
        parsed = JSON.parse(result.encoded)
        expect(parsed.dig("debugger", "snapshot", "captures", "lines", "42", "locals", "items")).to eq("pruned" => true)
        expect(result.encoded).not_to include("elements")
      end
    end

    context "when the structural envelope alone exceeds the cap" do
      let(:huge_envelope) { snapshot({}) }

      before do
        huge_envelope[:service] = "s" * 2_000_000
      end

      it "returns nil so the caller drops the snapshot" do
        result = described_class.encode(huge_envelope, 1024)
        expect(result.encoded).to be_nil
        expect(result.pruned).to be(false)
      end
    end

    context "with a UTF-8 multibyte captured value" do
      let(:utf8) { snapshot(line_captures(u: {type: "String", value: "\u00e9" * 400})) }

      it "measures encoded size by bytes and produces valid JSON" do
        result = described_class.encode(utf8, 2_000)
        expect(result.encoded.bytesize).to be <= 2_000
        JSON.parse(result.encoded)
      end
    end

    context "pruning preserves the variable name key" do
      let(:named) { snapshot(line_captures(a: {type: "Integer", value: "1"}, b: {type: "Integer", value: "1"})) }

      before do
        named.dig(:debugger, :snapshot, :captures, :lines, 42, :locals, :a)[:value] = "9" * 500_000
      end

      it "keeps the JSON key for the pruned slot" do
        result = described_class.encode(named, cap)
        parsed = JSON.parse(result.encoded)
        locals = parsed.dig("debugger", "snapshot", "captures", "lines", "42", "locals")
        expect(locals.key?("a")).to be(true)
        expect(locals["a"]).to eq("pruned" => true)
        expect(locals["b"]).to eq("type" => "Integer", "value" => "1")
      end
    end
  end
end
