require "spec_helper"
require "datadog/di/snapshot_encoder"
require "json"

RSpec.describe Datadog::DI::SnapshotEncoder do
  let(:cap) { 1024 * 1024 }

  # Records every value passed to JSON.dump, so tests can assert how many
  # times each captured value was encoded. The block is eager so the
  # spying stub is installed before each example encodes.
  let!(:dump_args) do
    args = []
    allow(JSON).to receive(:dump).and_wrap_original do |method, value|
      args << value
      method.call(value)
    end
    args
  end

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

  def captured_locals(result)
    parse(result).dig("debugger", "snapshot", "captures", "lines", "42", "locals")
  end

  # Encodes a Custom slot whose +field+ holds +value+ of the wrong type and
  # asserts the field is emitted as generic JSON without pruning.
  def expect_generic_json_field(field, value)
    result = described_class.encode(
      snapshot(line_captures(c: {"type" => "Custom", field => value})), cap,
    )
    expect(result.pruned).to be(false)
    expect(captured_locals(result)["c"]).to eq("type" => "Custom", field => value)
  end

  describe ".encode" do
    context "when the snapshot is under the cap" do
      let(:small) { snapshot(line_captures(x: {type: "Integer", value: "5"})) }

      it "encodes the snapshot unchanged" do
        result = described_class.encode(small, cap)
        expect(result.encoded).to eq(JSON.dump(small))
        expect(result.pruned).to be(false)
        expect(result.bytes).to be_nil
      end
    end

    context "when a captured integer fits the cap" do
      let(:big) do
        snapshot(line_captures(big: {type: "Integer", value: "9" * 500_000},
          small: {type: "Integer", value: "1"}))
      end

      it "encodes the integer and keeps the snapshot under the cap" do
        result = described_class.encode(big, cap)
        expect(result.pruned).to be(false)
        expect(result.encoded.bytesize).to be <= cap
        locals = captured_locals(result)
        expect(locals["big"]).to eq("type" => "Integer", "value" => "9" * 500_000)
        expect(locals["small"]).to eq("type" => "Integer", "value" => "1")
      end
    end

    context "when a single captured integer exceeds the cap" do
      let(:big) do
        snapshot(line_captures(big: {type: "Integer", value: "9" * 2_000_000},
          small: {type: "Integer", value: "1"}))
      end

      it "prunes the oversized slot to the marker and skips encoding the value" do
        result = described_class.encode(big, cap)
        expect(result.pruned).to be(true)
        expect(result.encoded.bytesize).to be <= cap
        locals = captured_locals(result)
        expect(locals["big"]).to eq("pruned" => true)
        expect(locals["small"]).to eq("type" => "Integer", "value" => "1")
        expect(result.encoded).not_to include("9" * 1000)
        expect(dump_args).not_to include("9" * 2_000_000)
      end

      it "encodes each captured string value at most once" do
        described_class.encode(big, cap)
        counts = dump_args.each_with_object(Hash.new(0)) do |value, agg|
          agg[value.object_id] += 1 if String === value
        end
        expect(counts.values.max).to be <= 1
      end
    end

    context "when a single captured string exceeds the cap" do
      let(:bigstr) do
        snapshot(line_captures(s: {type: "String", value: "x" * 2_000_000}))
      end

      it "prunes the oversized string slot to the marker" do
        result = described_class.encode(bigstr, cap)
        expect(result.pruned).to be(true)
        expect(result.encoded.bytesize).to be <= cap
        expect(captured_locals(result)["s"]).to eq("pruned" => true)
      end
    end

    context "when a collection slot's upper bound exceeds the budget" do
      let(:big_collection) do
        snapshot(line_captures(items: {type: "Array", elements: Array.new(10) { |i| {type: "Integer", value: "v#{i}"} }}))
      end

      it "prunes the whole collection slot and skips encoding its items" do
        result = described_class.encode(big_collection, 2_000)
        expect(result.pruned).to be(true)
        expect(result.encoded.bytesize).to be <= 2_000
        expect(captured_locals(result)["items"]).to eq("pruned" => true)
        expect(result.encoded).not_to include("elements")
        Array.new(10) { |i| "v#{i}" }.each do |item|
          expect(dump_args).not_to include(item)
        end
      end
    end

    context "when the structural envelope alone exceeds the cap" do
      let(:huge_envelope) { snapshot({}).merge(service: "s" * 2_000_000) }

      it "returns nil so the caller drops the snapshot" do
        result = described_class.encode(huge_envelope, 1024)
        expect(result.encoded).to be_nil
        expect(result.pruned).to be(false)
        expect(result.bytes).to be_between(1, 1024)
      end
    end

    context "when a captured object fits the budget" do
      let(:object_slot) do
        {type: "Obj", fields: {a: {type: "Integer", value: "1"}, b: {type: "String", value: "hi"}}}
      end

      it "keeps the object with its fields" do
        result = described_class.encode(snapshot(line_captures(o: object_slot)), cap)
        expect(result.pruned).to be(false)
        expect(captured_locals(result)["o"]).to eq(
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
        expect(captured_locals(result)["a"]).to eq(
          "type" => "Array",
          "elements" => [
            {"type" => "Integer", "value" => "1"},
            {"type" => "String", "value" => "x"},
          ],
        )
      end

      context "when an array member exceeds the member byte cap" do
        let(:members) do
          [{type: "String", value: "x" * 10_000}, {type: "Integer", value: "1"}]
        end

        it "prunes a member that exceeds the member cap and keeps the members after it" do
          result = described_class.encode(snapshot(line_captures(a: {type: "Array", elements: members})), cap)
          expect(result.pruned).to be(true)
          expect(result.encoded.bytesize).to be <= cap
          elements = captured_locals(result)["a"]["elements"]
          expect(elements.first).to eq("pruned" => true)
          expect(elements.last).to eq("type" => "Integer", "value" => "1")
        end
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
        expect(captured_locals(result)["h"]).to eq(
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
        expect(captured_locals(result)["u"]).to eq("type" => "String", "value" => "あ" * 255)
      end

      it "prunes the value when its encoded bytes exceed the budget" do
        # A 255-character budget would fit this value (255 characters,
        # 765 bytes); a byte budget of this size must prune it.
        result = described_class.encode(utf8, empty_base + 400)
        expect(result.pruned).to be(true)
        expect(result.encoded.bytesize).to be <= empty_base + 400
        expect(captured_locals(result)["u"]).to eq("pruned" => true)
      end
    end

    context "when a captured collection holds a nested collection" do
      let(:nested) { {type: "Array", elements: [{type: "Integer", value: "1"}]} }

      let(:fitting_slot) do
        {type: "Array", elements: [nested, {type: "Integer", value: "2"}]}
      end

      let(:oversized_nested) do
        {type: "Array", elements: Array.new(2_000) { {type: "Integer", value: "1"} }}
      end

      let(:oversized_slot) do
        {type: "Array", elements: [oversized_nested, {type: "Integer", value: "2"}]}
      end

      let(:level3) do
        {type: "NestedObject", fields: {
          level: {type: "Integer", value: "3"},
          "@nested": {type: "NestedObject", notCapturedReason: "depth"},
        }}
      end

      let(:level2) do
        {type: "NestedObject", fields: {
          level: {type: "Integer", value: "2"},
          "@nested": level3,
        }}
      end

      let(:deep) do
        {type: "NestedObject", fields: {
          level: {type: "Integer", value: "1"},
          "@nested": level2,
        }}
      end

      it "keeps the nested collection member when the budget fits it" do
        result = described_class.encode(snapshot(line_captures(a: fitting_slot)), cap)
        expect(result.pruned).to be(false)
        expect(result.encoded.bytesize).to be <= cap
        elements = captured_locals(result)["a"]["elements"]
        expect(elements.first).to eq("type" => "Array", "elements" => [{"type" => "Integer", "value" => "1"}])
        expect(elements.last).to eq("type" => "Integer", "value" => "2")
      end

      it "keeps nested collections to the default capture depth" do
        result = described_class.encode(snapshot(line_captures(deepObject: deep)), cap)
        expect(result.pruned).to be(false)
        expect(result.encoded.bytesize).to be <= cap
        expect(captured_locals(result)["deepObject"].dig("fields", "@nested", "fields", "@nested", "fields", "@nested")).to eq(
          "type" => "NestedObject",
          "notCapturedReason" => "depth",
        )
      end

      it "prunes the nested collection member that exceeds the budget" do
        result = described_class.encode(snapshot(line_captures(a: oversized_slot)), cap)
        expect(result.pruned).to be(true)
        expect(result.encoded.bytesize).to be <= cap
        elements = captured_locals(result)["a"]["elements"]
        expect(elements.first).to eq("pruned" => true)
        expect(elements.last).to eq("type" => "Integer", "value" => "2")
      end
    end

    context "when a captured object holds nested objects" do
      let(:slot) do
        {type: "L1", fields: {nested: {type: "L2", fields: {
          nested: {type: "L3", fields: {leaf: {type: "Integer", value: "1"}}},
        }}}}
      end

      it "keeps the nested objects within the capture depth" do
        result = described_class.encode(snapshot(line_captures(a: slot)), cap)
        expect(result.pruned).to be(false)
        expect(result.encoded.bytesize).to be <= cap
        expect(captured_locals(result)["a"]).to eq(
          "type" => "L1",
          "fields" => {"nested" => {
            "type" => "L2",
            "fields" => {"nested" => {
              "type" => "L3",
              "fields" => {"leaf" => {"type" => "Integer", "value" => "1"}},
            }},
          }},
        )
      end
    end

    context "with capture expressions" do
      let(:expressions) do
        snapshot({entry: {captureExpressions: {
          big: {type: "Integer", value: "9" * 2_000_000},
          small: {type: "Integer", value: "1"},
        }}})
      end

      it "prunes the oversized expression value and keeps the small one" do
        result = described_class.encode(expressions, cap)
        expect(result.pruned).to be(true)
        expect(result.encoded.bytesize).to be <= cap
        captured = parse(result).dig("debugger", "snapshot", "captures", "entry", "captureExpressions")
        expect(captured["big"]).to eq("pruned" => true)
        expect(captured["small"]).to eq("type" => "Integer", "value" => "1")
      end

      let(:fitting) do
        snapshot({entry: {captureExpressions: {x: {type: "Integer", value: "1"}}}})
      end

      it "encodes fitting capture expressions unchanged" do
        result = described_class.encode(fitting, cap)
        expect(result.pruned).to be(false)
        captured = parse(result).dig("debugger", "snapshot", "captures", "entry", "captureExpressions")
        expect(captured).to eq("x" => {"type" => "Integer", "value" => "1"})
      end
    end

    context "with many small retained slots" do
      let(:many) do
        snapshot(line_captures(30.times.map { |i| ["v#{i}", {type: "Integer", value: "1"}] }.to_h))
      end

      it "keeps every slot under a cap that fits them all" do
        result = described_class.encode(many, cap)
        expect(result.pruned).to be(false)
        expect(result.encoded.bytesize).to be <= cap
        expect(captured_locals(result).keys).to eq(30.times.map { |i| "v#{i}" })
      end

      it "returns nil or JSON within the cap for every cap" do
        full = JSON.dump(many).bytesize
        expect(described_class.encode(many, 1).encoded).to be_nil
        result = described_class.encode(many, full)
        expect(result.encoded).not_to be_nil
        expect(result.encoded.bytesize).to be <= full
        expect { JSON.parse(result.encoded) }.not_to raise_error
        0.step(full + 50, 1) do |capped|
          sweep_result = described_class.encode(many, capped)
          next if sweep_result.encoded.nil?
          expect(sweep_result.encoded.bytesize).to be <= capped
          expect { JSON.parse(sweep_result.encoded) }.not_to raise_error
        end
      end
    end

    context "when a custom serializer slot carries an unknown field" do
      it "encodes the unknown field name and value" do
        result = described_class.encode(snapshot(line_captures(c: {type: "Custom", customField: "x"})), cap)
        expect(result.pruned).to be(false)
        expect(captured_locals(result)["c"]).to eq("type" => "Custom", "customField" => "x")
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
        expect(captured_locals(result)["x"]).to eq("pruned" => true)
        expect(result.encoded).not_to include("\\u0001")
      end
    end

    context "when a slot value is a raw string" do
      it "encodes the raw string" do
        result = described_class.encode(snapshot(line_captures(raw: "hello")), cap)
        expect(result.pruned).to be(false)
        expect(captured_locals(result)["raw"]).to eq("hello")
      end

      it "prunes a raw string that exceeds the budget" do
        result = described_class.encode(snapshot(line_captures(raw: "x" * 2_000_000)), cap)
        expect(result.pruned).to be(true)
        expect(result.encoded.bytesize).to be <= cap
        expect(captured_locals(result)["raw"]).to eq("pruned" => true)
      end
    end

    context "when a slot value is a raw array" do
      it "encodes the raw array" do
        result = described_class.encode(snapshot(line_captures(raw: [1, "two", nil])), cap)
        expect(result.pruned).to be(false)
        expect(captured_locals(result)["raw"]).to eq([1, "two", nil])
      end
    end

    context "when a slot value cannot be JSON-encoded" do
      # The asserted class is stable across the json matrix: below json
      # 2.6 the gem raises Encoding::UndefinedConversionError for a value
      # it cannot convert to UTF-8, and json 2.6 and later raise
      # JSON::GeneratorError; SnapshotEncoder.json_dump normalizes both
      # to JSON::GeneratorError.
      it "raises the encoding error" do
        expect do
          described_class.encode(snapshot(line_captures(raw: "\x80".b)), cap)
        end.to raise_error(JSON::GeneratorError)
      end
    end

    context "when a slot field holds a value of the wrong type" do
      it "encodes the elements value as generic JSON" do
        expect_generic_json_field("elements", "junk")
      end

      it "encodes the entries value as generic JSON" do
        expect_generic_json_field("entries", "junk")
      end

      it "encodes a String pair as generic JSON" do
        expect_generic_json_field("entries", ["junk"])
      end

      it "encodes a three-member pair as generic JSON" do
        expect_generic_json_field("entries", [
          [
            {"type" => "String", "value" => "k"},
            {"type" => "String", "value" => "v"},
            {"type" => "String", "value" => "w"},
          ],
        ])
      end

      it "encodes a one-member pair as generic JSON" do
        expect_generic_json_field("entries", [[{"type" => "String", "value" => "k"}]])
      end

      it "encodes the fields value as generic JSON" do
        expect_generic_json_field("fields", 7)
      end

      it "encodes the locals value as generic JSON" do
        result = described_class.encode(
          snapshot({lines: {42 => {locals: "junk", arguments: {}}}}), cap,
        )
        expect(result.pruned).to be(false)
        expect(captured_locals(result)).to eq("junk")
      end
    end

    context "when a captured value reports a serialization failure" do
      let(:reason) { snapshot(line_captures(w: {type: "Weird", notSerializedReason: "boom " * 1000})) }

      it "keeps the failure reason when it fits" do
        result = described_class.encode(reason, cap)
        expect(result.pruned).to be(false)
        expect(captured_locals(result)["w"]).to eq("type" => "Weird", "notSerializedReason" => "boom " * 1000)
      end

      it "prunes the slot when the failure reason exceeds the budget" do
        result = described_class.encode(reason, 2_000)
        expect(result.pruned).to be(true)
        expect(result.encoded.bytesize).to be <= 2_000
        expect(captured_locals(result)["w"]).to eq("pruned" => true)
      end
    end

    context "with a captured throwable" do
      let(:throwable) do
        {type: "RuntimeError", message: "boom", stacktrace: [{fileName: "a.rb", function: "x", lineNumber: 1}]}
      end

      it "encodes the throwable with its message and stacktrace" do
        result = described_class.encode(
          snapshot({lines: {42 => {locals: {x: {type: "Integer", value: "1"}}, throwable: throwable}}}), cap,
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
          snapshot({lines: {42 => {locals: {x: {type: "Integer", value: "1"}}, throwable: nil}}}), cap,
        )
        expect(result.pruned).to be(false)
        expect(parse(result).dig("debugger", "snapshot", "captures", "lines", "42", "throwable")).to be_nil
      end

      let(:huge) { {type: "RuntimeError", message: "m" * 2_000, stacktrace: []} }

      it "prunes a throwable that exceeds the budget" do
        result = described_class.encode(
          snapshot({lines: {42 => {locals: {x: {type: "Integer", value: "1"}}, throwable: huge}}}), 2_000,
        )
        expect(result.pruned).to be(true)
        expect(result.encoded.bytesize).to be <= 2_000
        expect(parse(result).dig("debugger", "snapshot", "captures", "lines", "42", "throwable")).to eq("pruned" => true)
      end
    end

    context "when the budget cannot fit the pruned marker" do
      let(:sized) { snapshot(line_captures(s: {type: "String", value: "x" * 3_000})) }
      let(:full) { JSON.dump(snapshot(line_captures(s: {type: "String", value: ""}))).bytesize }
      let(:pruned_size) { JSON.dump(snapshot(line_captures(s: {"pruned" => true}))).bytesize }

      it "returns nil or valid JSON within the cap for every cap" do
        expect(described_class.encode(sized, pruned_size - 1).encoded).to be_nil
        result = described_class.encode(sized, pruned_size)
        expect(result.encoded).not_to be_nil
        expect(result.pruned).to be(true)
        expect(result.encoded.bytesize).to be <= pruned_size
        expect(captured_locals(result)["s"]).to eq("pruned" => true)
        0.step(full + 50, 1) do |capped|
          sweep_result = described_class.encode(sized, capped)
          next if sweep_result.encoded.nil?
          expect(sweep_result.encoded.bytesize).to be <= capped
          expect { JSON.parse(sweep_result.encoded) }.not_to raise_error
        end
      end
    end
  end
end
