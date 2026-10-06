require "spec_helper"
require "datadog/di/snapshot_encoder"
require "json"

RSpec.describe Datadog::DI::SnapshotEncoder do
  let(:cap) { 1024 * 1024 }

  # Builds a snapshot Hash in the shape ProbeNotificationBuilder produces.
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

  def parse(result)
    JSON.parse(result.encoded)
  end

  def locals_of(result)
    parse(result).dig("debugger", "snapshot", "captures", "lines", "42", "locals")
  end

  # Records every value passed to JSON.dump during the block, so tests can
  # assert how many times each captured value was encoded.
  def dump_args
    @dump_args = []
    allow(JSON).to receive(:dump).and_wrap_original do |method, value|
      @dump_args << value
      method.call(value)
    end
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

    context "when a captured integer fits the cap" do
      let(:big) { snapshot(line_captures(big: {type: "Integer", value: "1"}, small: {type: "Integer", value: "1"})) }

      before do
        big.dig(:debugger, :snapshot, :captures, :lines, 42, :locals, :big)[:value] = "9" * 500_000
      end

      it "encodes the integer and keeps the snapshot under the cap" do
        result = described_class.encode(big, cap)
        expect(result.pruned).to be(false)
        expect(result.encoded.bytesize).to be <= cap
        locals = locals_of(result)
        expect(locals["big"]).to eq("type" => "Integer", "value" => "9" * 500_000)
        expect(locals["small"]).to eq("type" => "Integer", "value" => "1")
      end
    end

    context "when a single captured integer exceeds the cap" do
      let(:big) { snapshot(line_captures(big: {type: "Integer", value: "1"}, small: {type: "Integer", value: "1"})) }

      before do
        big.dig(:debugger, :snapshot, :captures, :lines, 42, :locals, :big)[:value] = "9" * 2_000_000
      end

      it "prunes the oversized slot to the marker without encoding the value" do
        dump_args
        result = described_class.encode(big, cap)
        expect(result.pruned).to be(true)
        expect(result.encoded.bytesize).to be <= cap
        locals = locals_of(result)
        expect(locals["big"]).to eq("pruned" => true)
        expect(locals["small"]).to eq("type" => "Integer", "value" => "1")
        expect(result.encoded).not_to include("9" * 1000)
        expect(@dump_args).not_to include("9" * 2_000_000)
      end

      it "encodes each captured string value at most once" do
        dump_args
        described_class.encode(big, cap)
        counts = @dump_args.each_with_object(Hash.new(0)) do |value, agg|
          agg[value.object_id] += 1 if String === value
        end
        expect(counts.values.max).to be <= 1
      end
    end

    context "when a single captured string exceeds the cap" do
      let(:bigstr) { snapshot(line_captures(s: {type: "String", value: "x"})) }

      before do
        bigstr.dig(:debugger, :snapshot, :captures, :lines, 42, :locals, :s)[:value] = "x" * 2_000_000
      end

      it "prunes the oversized string slot to the marker" do
        result = described_class.encode(bigstr, cap)
        expect(result.pruned).to be(true)
        expect(result.encoded.bytesize).to be <= cap
        expect(locals_of(result)["s"]).to eq("pruned" => true)
      end
    end

    context "when a collection slot's lower bound exceeds the budget" do
      let(:big_collection) do
        snapshot(line_captures(items: {type: "Array", elements: Array.new(10) { |i| {type: "Integer", value: "v#{i}"} }}))
      end

      it "prunes the whole collection slot without encoding its items" do
        dump_args
        result = described_class.encode(big_collection, 2_000)
        expect(result.pruned).to be(true)
        expect(result.encoded.bytesize).to be <= 2_000
        expect(locals_of(result)["items"]).to eq("pruned" => true)
        expect(result.encoded).not_to include("elements")
        Array.new(10) { |i| "v#{i}" }.each do |item|
          expect(@dump_args).not_to include(item)
        end
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

    context "when a captured object fits the budget" do
      let(:object_slot) do
        {type: "Obj", fields: {a: {type: "Integer", value: "1"}, b: {type: "String", value: "hi"}}}
      end

      it "keeps the object with its fields" do
        result = described_class.encode(snapshot(line_captures(o: object_slot)), cap)
        expect(result.pruned).to be(false)
        expect(locals_of(result)["o"]).to eq(
          "type" => "Obj",
          "fields" => {
            "a" => {"type" => "Integer", "value" => "1"},
            "b" => {"type" => "String", "value" => "hi"},
          },
        )
      end
    end

    context "when a captured array fits the budget" do
      let(:array_slot) do
        {type: "Array", elements: [{type: "Integer", value: "1"}, {type: "String", value: "x"}]}
      end

      it "keeps the array with its elements" do
        result = described_class.encode(snapshot(line_captures(a: array_slot)), cap)
        expect(result.pruned).to be(false)
        expect(locals_of(result)["a"]).to eq(
          "type" => "Array",
          "elements" => [
            {"type" => "Integer", "value" => "1"},
            {"type" => "String", "value" => "x"},
          ],
        )
      end

      it "prunes a member that exceeds the member cap and keeps the members before it" do
        members = [{type: "String", value: "x" * 10_000}, {type: "Integer", value: "1"}]
        result = described_class.encode(snapshot(line_captures(a: {type: "Array", elements: members})), cap)
        expect(result.pruned).to be(true)
        expect(result.encoded.bytesize).to be <= cap
        elements = locals_of(result)["a"]["elements"]
        expect(elements.first).to eq("pruned" => true)
        expect(elements.last).to eq("type" => "Integer", "value" => "1")
      end
    end

    context "when a captured hash fits the budget" do
      let(:hash_slot) do
        {
          type: "Hash",
          entries: [
            [{type: "String", value: "k"}, {type: "Integer", value: "1"}],
            [{type: "String", value: "j"}, {type: "Integer", value: "2"}],
          ],
        }
      end

      it "keeps the hash with its entries" do
        result = described_class.encode(snapshot(line_captures(h: hash_slot)), cap)
        expect(result.pruned).to be(false)
        expect(locals_of(result)["h"]).to eq(
          "type" => "Hash",
          "entries" => [
            [
              {"type" => "String", "value" => "k"},
              {"type" => "Integer", "value" => "1"},
            ],
            [
              {"type" => "String", "value" => "j"},
              {"type" => "Integer", "value" => "2"},
            ],
          ],
        )
      end
    end

    context "with a UTF-8 multibyte captured value" do
      let(:utf8) { snapshot(line_captures(u: {type: "String", value: "あ" * 255})) }
      let(:empty_base) { JSON.dump(snapshot(line_captures(u: {type: "String", value: ""}))).bytesize }

      it "keeps the value when its encoded bytes fit" do
        result = described_class.encode(utf8, cap)
        expect(result.pruned).to be(false)
        expect(result.encoded.bytesize).to be <= cap
        expect(locals_of(result)["u"]).to eq("type" => "String", "value" => "あ" * 255)
      end

      it "prunes the value when its encoded bytes do not fit, measuring by bytes" do
        # A 255-character budget would fit this value (255 characters,
        # 765 bytes); a byte budget of this size must prune it.
        result = described_class.encode(utf8, empty_base + 400)
        expect(result.pruned).to be(true)
        expect(result.encoded.bytesize).to be <= empty_base + 400
        expect(locals_of(result)["u"]).to eq("pruned" => true)
      end
    end

    context "when a captured value exceeds its slot mid-encoding" do
      let(:escaping) { snapshot(line_captures(x: {type: "String", value: "\u0001" * 100})) }
      let(:empty_base) { JSON.dump(snapshot(line_captures(x: {type: "String", value: ""}))).bytesize }

      it "prunes the slot together with its partial emission" do
        # The value's bytes fit a byte budget four times its size, but its
        # encoding expands control characters six-fold and overflows
        # mid-encoding.
        result = described_class.encode(escaping, empty_base + 400)
        expect(result.pruned).to be(true)
        expect(result.encoded.bytesize).to be <= empty_base + 400
        expect(locals_of(result)["x"]).to eq("pruned" => true)
        expect(result.encoded).not_to include("\\u0001")
      end
    end

    context "pruning preserves the variable name key" do
      let(:named) { snapshot(line_captures(a: {type: "Integer", value: "1"}, b: {type: "Integer", value: "1"})) }

      before do
        named.dig(:debugger, :snapshot, :captures, :lines, 42, :locals, :a)[:value] = "9" * 2_000_000
      end

      it "keeps the JSON key for the pruned slot" do
        result = described_class.encode(named, cap)
        locals = locals_of(result)
        expect(locals.key?("a")).to be(true)
        expect(locals["a"]).to eq("pruned" => true)
        expect(locals["b"]).to eq("type" => "Integer", "value" => "1")
      end
    end

    context "when a slot value is a raw string" do
      it "encodes the raw string" do
        result = described_class.encode(snapshot(line_captures(raw: "hello")), cap)
        expect(result.pruned).to be(false)
        expect(locals_of(result)["raw"]).to eq("hello")
      end

      it "prunes a raw string that exceeds the budget" do
        result = described_class.encode(snapshot(line_captures(raw: "x" * 2_000_000)), cap)
        expect(result.pruned).to be(true)
        expect(result.encoded.bytesize).to be <= cap
        expect(locals_of(result)["raw"]).to eq("pruned" => true)
      end
    end

    context "when a slot value is a raw array" do
      it "encodes the raw array" do
        result = described_class.encode(snapshot(line_captures(raw: [1, "two", nil])), cap)
        expect(result.pruned).to be(false)
        expect(locals_of(result)["raw"]).to eq([1, "two", nil])
      end
    end

    context "when a slot value cannot be JSON-encoded" do
      it "raises the encoding error" do
        expect do
          described_class.encode(snapshot(line_captures(raw: "\x80".b)), cap)
        end.to raise_error(JSON::GeneratorError)
      end
    end

    context "when a slot field holds a value of the wrong type" do
      it "encodes the elements value as generic JSON" do
        result = described_class.encode(
          snapshot(line_captures(c: {type: "Custom", elements: "junk"})), cap
        )
        expect(result.pruned).to be(false)
        expect(locals_of(result)["c"]).to eq("type" => "Custom", "elements" => "junk")
      end

      it "encodes the entries value as generic JSON" do
        result = described_class.encode(
          snapshot(line_captures(c: {type: "Custom", entries: "junk"})), cap
        )
        expect(result.pruned).to be(false)
        expect(locals_of(result)["c"]).to eq("type" => "Custom", "entries" => "junk")
      end

      it "encodes a pair that is not an array as generic JSON" do
        result = described_class.encode(
          snapshot(line_captures(c: {type: "Custom", entries: ["junk"]})), cap
        )
        expect(result.pruned).to be(false)
        expect(locals_of(result)["c"]).to eq("type" => "Custom", "entries" => ["junk"])
      end

      it "encodes the fields value as generic JSON" do
        result = described_class.encode(
          snapshot(line_captures(c: {type: "Custom", fields: 7})), cap
        )
        expect(result.pruned).to be(false)
        expect(locals_of(result)["c"]).to eq("type" => "Custom", "fields" => 7)
      end
    end

    context "when a captured value reports a serialization failure" do
      let(:reason) { snapshot(line_captures(w: {type: "Weird", notSerializedReason: "boom " * 1000})) }

      it "keeps the failure reason when it fits" do
        result = described_class.encode(reason, cap)
        expect(result.pruned).to be(false)
        expect(locals_of(result)["w"]).to eq("type" => "Weird", "notSerializedReason" => "boom " * 1000)
      end

      it "prunes the slot when the failure reason exceeds the budget" do
        result = described_class.encode(reason, 2_000)
        expect(result.pruned).to be(true)
        expect(result.encoded.bytesize).to be <= 2_000
        expect(locals_of(result)["w"]).to eq("pruned" => true)
      end
    end

    context "with a captured throwable" do
      let(:throwable) do
        {type: "RuntimeError", message: "boom", stacktrace: [{fileName: "a.rb", function: "x", lineNumber: 1}]}
      end

      it "encodes the throwable with its message and stacktrace" do
        result = described_class.encode(
          snapshot({lines: {42 => {locals: {x: {type: "Integer", value: "1"}}, throwable: throwable}}}), cap
        )
        expect(result.pruned).to be(false)
        captured = parse(result).dig("debugger", "snapshot", "captures", "lines", "42", "throwable")
        expect(captured).to eq(
          "type" => "RuntimeError",
          "message" => "boom",
          "stacktrace" => [{"fileName" => "a.rb", "function" => "x", "lineNumber" => 1}],
        )
      end

      it "encodes a nil throwable" do
        result = described_class.encode(
          snapshot({lines: {42 => {locals: {x: {type: "Integer", value: "1"}}, throwable: nil}}}), cap
        )
        expect(result.pruned).to be(false)
        expect(parse(result).dig("debugger", "snapshot", "captures", "lines", "42", "throwable")).to be_nil
      end

      it "prunes a throwable that exceeds the budget" do
        huge = {type: "RuntimeError", message: "m" * 2_000, stacktrace: []}
        result = described_class.encode(
          snapshot({lines: {42 => {locals: {x: {type: "Integer", value: "1"}}, throwable: huge}}}), 2_000
        )
        expect(result.pruned).to be(true)
        expect(result.encoded.bytesize).to be <= 2_000
        expect(parse(result).dig("debugger", "snapshot", "captures", "lines", "42", "throwable")).to eq("pruned" => true)
      end
    end

    context "when the budget leaves no room for the pruned marker" do
      let(:sized) { snapshot(line_captures(s: {type: "String", value: "x" * 3_000})) }
      let(:full) { JSON.dump(snapshot(line_captures(s: {type: "String", value: ""}))).bytesize }

      it "returns nil or valid JSON within the cap for every cap" do
        0.step(full + 50, 1) do |capped|
          result = described_class.encode(sized, capped)
          next if result.encoded.nil?
          expect(result.encoded.bytesize).to be <= capped
          expect { JSON.parse(result.encoded) }.not_to raise_error
        end
      end
    end
  end
end
