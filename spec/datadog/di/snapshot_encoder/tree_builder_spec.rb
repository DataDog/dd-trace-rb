require "datadog/di/spec_helper"
require_relative "../snapshot_encoder_helpers"

# A String subclass whose JSON encoding is overridden.
class TreeBuilderSpecOverridingString < String
  def to_json(*)
    '"overridden"'
  end
end

# A String subclass without a JSON override.
class TreeBuilderSpecPlainString < String
end

# An object encoded through its to_s.
class TreeBuilderSpecDescribedObject
  def to_s
    "described"
  end
end

# An object with its own JSON encoding.
class TreeBuilderSpecEncodedObject
  def to_json(*)
    '{"encoded":1}'
  end
end

# An object whose to_s returns a String subclass with a JSON override.
class TreeBuilderSpecOverridingToS
  def to_s
    TreeBuilderSpecOverridingString.new("name")
  end
end

# An object whose to_s returns an Integer.
class TreeBuilderSpecIntegerToS
  def to_s
    5
  end
end

# An object whose to_s returns an Array.
class TreeBuilderSpecArrayToS
  def to_s
    [1]
  end
end

# A Hash subclass without overrides.
class TreeBuilderSpecPlainHash < Hash
end

# An Array subclass without overrides.
class TreeBuilderSpecPlainArray < Array
end

# A Hash subclass overriding its JSON encoding and its iteration.
class TreeBuilderSpecOverridingHash < Hash
  def to_json(*)
    raise "Hash#to_json override called"
  end

  def each(*)
    raise "Hash#each override called"
  end

  def each_pair(*)
    raise "Hash#each_pair override called"
  end
end

# An Array subclass overriding its JSON encoding and its iteration.
class TreeBuilderSpecOverridingArray < Array
  def to_json(*)
    raise "Array#to_json override called"
  end

  def each(*)
    raise "Array#each override called"
  end
end

# A Hash subclass overriding keys.
class TreeBuilderSpecKeysHash < Hash
  def keys
    ["absent"]
  end
end

RSpec.describe Datadog::DI::SnapshotEncoder::TreeBuilder do
  include SnapshotEncoderHelpers

  subject(:builder) { described_class.new }

  let(:build) { builder.build(payload) }
  let(:root) { build[0] }
  let(:step1_candidates) { build[1] }
  let(:step2_candidates) { build[2] }
  let(:collections) { build[3] }

  shared_examples "encodes as JSON.dump" do
    it "emits the bytes of JSON.dump with exact node sizes" do
      expect(emit(root)).to eq JSON.dump(payload)
      expect(root.size).to eq JSON.dump(payload).bytesize
      expect_exact_sizes(root)
    end
  end

  describe "#build" do
    it "raises ArgumentError for a payload that is not a Hash" do
      expect { builder.build([1]) }.to raise_error(ArgumentError, "snapshot payload must be a Hash: Array")
    end

    context "with the envelope only" do
      let(:payload) { snapshot_payload(captures: {}) }

      include_examples "encodes as JSON.dump"

      it "registers nothing" do
        expect(step1_candidates).to be_empty
        expect(step2_candidates).to be_empty
        expect(collections).to be_empty
      end
    end

    context "with method probe captures" do
      let(:payload) do
        snapshot_payload(captures: {
          entry: {arguments: {arg1: string_value("a"), self: {type: "Target", fields: {"@x": {type: "Integer", value: "1"}}}}},
          return: {
            arguments: {"@return": array_value([string_value("b"), {type: "NilClass", isNull: true}])},
            throwable: nil,
          },
        })
      end

      include_examples "encodes as JSON.dump"
    end

    context "with line probe captures under an Integer key" do
      let(:payload) do
        snapshot_payload(captures: {
          lines: {42 => {locals: {count: {type: "Integer", value: "3"}}, arguments: {self: {type: "Target", fields: {}}}}},
        })
      end

      include_examples "encodes as JSON.dump"

      it "registers the capture set, its variable maps and its value collection" do
        expect(collections.map(&:depth)).to contain_exactly(0, 1, 1, 2)
      end
    end

    context "with a lines member that is not a Hash" do
      let(:payload) { snapshot_payload(captures: {lines: {3 => [string_value("x" * 300)]}}) }

      include_examples "encodes as JSON.dump"

      it "treats the member as envelope" do
        expect(collections).to be_empty
        expect(step1_candidates).to be_empty
      end
    end

    context "with a line probe without locals" do
      let(:payload) { snapshot_payload(captures: {lines: nil}) }

      include_examples "encodes as JSON.dump"

      it "treats the nil lines member as envelope" do
        expect(collections).to be_empty
      end
    end

    context "with scalars of every kind" do
      let(:payload) do
        return_payload(array_value([
          {type: "TrueClass", value: true},
          {type: "FalseClass", value: false},
          {type: "Float", value: 1.5},
          {type: "Float", value: Float::INFINITY},
          {type: "Integer", value: 12_345_678_901_234_567_890},
          {type: "Symbol", value: :sym},
          string_value("caf\u00e9 \u65e5\u672c \u{1f600}"),
          string_value("tab\tnewline\ncontrol\u0001quote\"backslash\\"),
          string_value("b'\\x80\\xff'"),
        ]))
      end

      include_examples "encodes as JSON.dump"
    end

    context "with a throwable" do
      let(:payload) do
        snapshot_payload(captures: {
          entry: {arguments: {}},
          return: {
            arguments: {},
            throwable: {
              type: "RuntimeError",
              message: "m" * 5_000,
              stacktrace: [{fileName: "/app/a.rb", function: "run", lineNumber: 1}] * 3,
            },
          },
        })
      end

      include_examples "encodes as JSON.dump"

      it "registers the throwable at depth 1 with its frames at depth 2" do
        throwable = collections.find { |collection| collection.element_member == "stacktrace" }
        expect(throwable.depth).to eq 1
        expect(throwable.element_count).to eq 3
      end

      it "keeps the message out of the step 1 candidates" do
        expect(step1_candidates).to be_empty
      end
    end

    context "with a throwable without a stacktrace" do
      let(:payload) do
        snapshot_payload(captures: {return: {arguments: {}, throwable: {type: "RuntimeError", message: "m" * 300}}})
      end

      it "registers the throwable as a primitive at depth 1" do
        expect(step1_candidates.map(&:depth)).to eq [1]
      end
    end

    context "with custom serializer output holding nested Hashes" do
      let(:payload) do
        return_payload({type: "Custom", data: {nested: {deeper: [1, {k: "v"}]}}, list: [[1, 2], {a: nil}]})
      end

      include_examples "encodes as JSON.dump"

      it "encodes the output as one primitive" do
        expect(collections.map(&:depth)).to contain_exactly(0, 0, 1, 1)
      end
    end

    if Gem::Version.new(JSON::VERSION) >= Gem::Version.new("2.6")
      context "with a BINARY string that is valid UTF-8" do
        let(:payload) { return_payload(string_value("caf\u00e9".b)) }

        include_examples "encodes as JSON.dump"
      end
    end

    context "with objects and String subclasses" do
      let(:payload) do
        return_payload({
          type: "Custom",
          plain_string: TreeBuilderSpecPlainString.new("plain"),
          overriding_string: TreeBuilderSpecOverridingString.new("ignored"),
          described: TreeBuilderSpecDescribedObject.new,
          encoded: TreeBuilderSpecEncodedObject.new,
          overriding_to_s: TreeBuilderSpecOverridingToS.new,
        })
      end

      include_examples "encodes as JSON.dump"
    end

    context "with an object whose to_s returns an Integer" do
      let(:payload) { return_payload({type: "Custom", value: TreeBuilderSpecIntegerToS.new}) }

      # json 2.9.1 and older raise TypeError for such an object; json
      # 2.18.0 encodes it.
      it "raises the error JSON.dump raises, or emits its bytes" do
        expected = begin
          JSON.dump(payload)
        rescue => exc
          exc.class
        end

        if expected.is_a?(String)
          expect(emit(root)).to eq expected
        else
          expect(expected).to eq TypeError
          expect { build }.to raise_error(expected)
        end
      end
    end

    context "with a key whose to_s returns an Integer" do
      let(:payload) { return_payload({TreeBuilderSpecIntegerToS.new => 1}) }

      it "raises TypeError naming both classes" do
        expect { build }.to raise_error(TypeError, "TreeBuilderSpecIntegerToS#to_s returned Integer, expected String")
      end
    end

    context "with a key whose to_s returns an Array" do
      let(:payload) { snapshot_payload(captures: {}).merge(TreeBuilderSpecArrayToS.new => 1) }

      it "raises TypeError naming both classes" do
        expect { build }.to raise_error(TypeError, "TreeBuilderSpecArrayToS#to_s returned Array, expected String")
      end
    end

    context "with a key whose to_s returns a String subclass overriding to_json" do
      let(:payload) { return_payload({:type => "Custom", TreeBuilderSpecOverridingToS.new => 1}) }

      include_examples "encodes as JSON.dump"

      it "encodes the name through the override instead of the member-name table" do
        dumped = []
        allow(JSON).to receive(:dump).and_wrap_original do |original, value|
          dumped << value
          original.call(value)
        end

        expect(emit(root)).to include('"overridden":1')
        expect(dumped.grep(TreeBuilderSpecOverridingString)).to eq ["name"]
      end
    end

    context "with Hash and Array subclasses without overrides" do
      let(:payload) do
        hash = TreeBuilderSpecPlainHash.new
        hash[:type] = "Hash"
        hash[:entries] = TreeBuilderSpecPlainArray.new([[string_value("k"), string_value("v")]])
        return_payload(hash)
      end

      include_examples "encodes as JSON.dump"
    end

    context "with Hash and Array subclasses overriding to_json and their iteration" do
      let(:overriding_hash) do
        TreeBuilderSpecOverridingHash.new.tap do |hash|
          hash[:type] = "Hash"
          hash[:data] = TreeBuilderSpecOverridingHash.new.tap { |nested| nested[:k] = 1 }
        end
      end
      let(:overriding_array) { TreeBuilderSpecOverridingArray.new([1, 2]) }
      let(:payload) { return_payload(array_value([overriding_hash, overriding_array])) }

      it "walks them as Hash and Array without calling the overrides" do
        expect(emit(root)).to eq JSON.dump(
          return_payload(array_value([{type: "Hash", data: {k: 1}}, [1, 2]])),
        )
        expect_exact_sizes(root)
      end
    end

    if JSON::VERSION == "2.1.0"
      context "with a Hash subclass overriding keys on json 2.1.0" do
        let(:payload) do
          return_payload(TreeBuilderSpecKeysHash.new.tap { |hash| hash[:type] = "Custom" })
        end

        it "encodes the actual entries" do
          expect(emit(root)).to eq JSON.dump(return_payload({type: "Custom"}))
        end
      end
    end

    context "with Symbol and String spellings of the role member names" do
      let(:payload) do
        {
          "service" => "s",
          "debugger" => {
            "snapshot" => {
              "captures" => {
                "return" => {
                  "arguments" => {
                    "@return" => {"type" => "Array", "elements" => [{"type" => "Integer", "value" => "1"}]},
                  },
                  "throwable" => {"type" => "E", "message" => "m", "stacktrace" => []},
                },
                "lines" => {"3" => {"locals" => {}, "captureExpressions" => {}}},
                "entry" => {"arguments" => {}},
              },
            },
          },
        }
      end

      include_examples "encodes as JSON.dump"

      it "recognizes the String spellings" do
        expect(collections.map(&:element_member).compact).to contain_exactly("elements", "stacktrace")
        expect(collections.count { |collection| collection.depth == 0 }).to eq 3
      end
    end

    context "when a Symbol and a String key match the same name" do
      let(:payload) do
        snapshot_payload(captures: {
          "return" => {arguments: {"@return": array_value([])}},
          :return => {arguments: {"@return": array_value([])}},
        })
      end

      include_examples "encodes as JSON.dump"

      it "uses the first in insertion order" do
        capture_set_ordinals = collections.select { |collection| collection.depth == 0 }.map(&:ordinal)
        expect(capture_set_ordinals).to eq [0]
      end
    end

    context "when a captured-value Hash has two element member spellings" do
      let(:payload) do
        return_payload({"elements" => "not an Array", :elements => [string_value("a")], :type => "Array"})
      end

      it "uses the first in insertion order and makes the Hash a primitive" do
        expect(collections.map(&:element_member).compact).to be_empty
      end
    end

    describe "classification" do
      let(:payload) { return_payload(value) }
      let(:return_value_registration) { collections.find { |collection| collection.depth == 2 } }

      {
        "fields" => {type: "Obj", fields: {a: {type: "Integer", value: "1"}}},
        "elements" => {type: "Array", elements: [{type: "Integer", value: "1"}]},
        "entries" => {type: "Hash", entries: [[{type: "Integer", value: "1"}, {type: "Integer", value: "2"}]]},
        "stacktrace" => {type: "E", message: "m", stacktrace: []},
      }.each do |element_member, captured_value|
        context "with a #{element_member} member" do
          let(:value) { captured_value }

          it "is a value collection with that element member" do
            expect(return_value_registration.element_member).to eq element_member
          end
        end
      end

      context "with several element members" do
        let(:value) { {type: "X", stacktrace: [], entries: [], elements: [], fields: {}} }

        it "takes fields, then elements, then entries, then stacktrace" do
          expect(return_value_registration.element_member).to eq "fields"
        end
      end

      context "with elements and entries" do
        let(:value) { {type: "X", entries: [], elements: []} }

        it "takes elements before entries" do
          expect(return_value_registration.element_member).to eq "elements"
        end
      end

      context "with entries and stacktrace" do
        let(:value) { {type: "X", stacktrace: [], entries: []} }

        it "takes entries before stacktrace" do
          expect(return_value_registration.element_member).to eq "entries"
        end
      end

      context "with an element member of the wrong class" do
        let(:value) { {type: "X", fields: [1], elements: {a: 1}} }

        it "is a primitive" do
          expect(return_value_registration).to be nil
        end
      end

      context "with a value member and an element member" do
        let(:value) { {type: "X", value: "v", elements: [1] * 30} }

        it "is a primitive" do
          expect(return_value_registration).to be nil
          expect(step2_candidates.map(&:depth)).to eq []
        end
      end

      context "with none of the members" do
        let(:value) { {type: "X", notCapturedReason: "depth"} }

        it "is a primitive" do
          expect(return_value_registration).to be nil
        end
      end

      context "with a non-Hash value" do
        let(:value) { ["x" * 300] }

        it "is a primitive" do
          expect(return_value_registration).to be nil
          expect(step1_candidates.map(&:depth)).to eq [2]
        end
      end

      context "with entries members of every shape" do
        let(:value) do
          {type: "Hash", entries: [
            [string_value("k" * 300), {type: "Array", elements: []}],
            {type: "Array", elements: []},
            [1, 2, 3],
          ]}
        end

        it "makes the pair members and the other members captured values" do
          expect(collections.map(&:element_member)).to include("entries", "elements", "elements")
          expect(step1_candidates.map(&:depth)).to eq [3]
          expect(collections.select { |collection| collection.element_member == "elements" }.map(&:depth))
            .to eq [3, 3]
          expect_exact_sizes(root)
        end
      end
    end

    context "with members outside debugger.snapshot.captures" do
      let(:payload) do
        snapshot_payload(captures: {
          entry: {arguments: {
            captures: {type: "Hash", entries: []},
            entry: string_value("x" * 300),
            return: {type: "Array", elements: [1] * 25},
            lines: {type: "Hash", entries: []},
          }},
        }).merge(
          message: "m" * 300,
          captures: {entry: {arguments: {a: string_value("x" * 300)}}},
          extra: {type: "Array", elements: [1] * 25},
        )
      end

      include_examples "encodes as JSON.dump"

      it "registers only the captured data under debugger.snapshot.captures" do
        expect(collections.map(&:depth)).to contain_exactly(0, 1, 2, 2, 2)
        expect(step1_candidates.map(&:depth)).to eq [2]
        expect(step2_candidates.map(&:depth)).to eq [2]
      end
    end

    describe "type values" do
      let(:payload) do
        return_payload(array_value([
          {type: "Klass", value: "1"},
          {type: "Klass", value: "2"},
          {type: :Klass, value: "3"},
          {type: :Klass, value: "4"},
          {type: TreeBuilderSpecPlainString.new("Klass"), value: "5"},
          {type: TreeBuilderSpecPlainString.new("Klass"), value: "6"},
          {type: nil, value: "7"},
          {type: 7, value: "8"},
          {type: true, value: "9"},
        ]))
      end

      include_examples "encodes as JSON.dump"

      it "encodes exactly-String and exactly-Symbol values once each and others per occurrence" do
        dumped = []
        allow(JSON).to receive(:dump).and_wrap_original do |original, value|
          dumped << value
          original.call(value)
        end

        build

        expect(dumped.count { |value| value == "Klass" && value.instance_of?(String) }).to eq 1
        expect(dumped.count { |value| value == :Klass }).to eq 1
        expect(dumped.count { |value| value.is_a?(TreeBuilderSpecPlainString) }).to eq 2
        expect(dumped).not_to include(nil, 7, true)
      end
    end

    describe "encoding each value once" do
      # The scalar values differ from every member name, so a member name
      # passed to JSON.dump is distinguishable from a value.
      let(:payload) do
        {debugger: {snapshot: {captures: {return: {arguments: {"@return": array_value([
          {type: "Obj", fields: {custom_name: {type: "Integer", value: 11}, custom_flag: {type: "Bool", value: true}}},
          {type: "Obj", fields: {custom_name: {type: "Integer", value: 12}, custom_flag: {type: "Bool", value: false}}},
          {type: "NilClass", isNull: true, value: nil},
          string_value("s1"),
          string_value("s2"),
        ])}}}}}}
      end

      it "passes each scalar occurrence to JSON.dump at most once and no Hash or Array" do
        dumped = []
        allow(JSON).to receive(:dump).and_wrap_original do |original, value|
          dumped << value
          original.call(value)
        end

        build

        expect(dumped.grep(Hash) + dumped.grep(Array)).to be_empty
        expect(dumped.count("custom_name")).to eq 1
        expect(dumped.count("custom_flag")).to eq 1
        expect(dumped & Datadog::DI::SnapshotEncoder::MEMBER_NAME_JSON.keys).to be_empty
        expect(dumped.count("s1")).to eq 1
        expect(dumped.count("Integer")).to eq 1
      end

      it "writes Integers with Integer#to_s once each and true, false and nil from frozen literals" do
        integer_values = []
        trace = TracePoint.new(:c_call) do |tp|
          integer_values << tp.self if tp.defined_class == Integer && tp.method_id == :to_s
        end
        trace.enable { build }

        expect(integer_values.count(11)).to eq 1
        expect(integer_values.count(12)).to eq 1
        expect(described_class::TRUE_JSON).to be_frozen
        expect(described_class::FALSE_JSON).to be_frozen
        expect(described_class::NULL_JSON).to be_frozen
        expect(emit(root)).to eq JSON.dump(payload)
      end
    end

    describe "iteration" do
      let(:payload) do
        return_payload(array_value([{type: "Obj", fields: {a: {type: "Custom", data: {x: [1, [2]]}}}}]))
      end

      it "iterates each payload Hash once and each payload Array once" do
        hash_count = 0
        array_count = 0
        hash_each_pair = described_class::HASH_EACH_PAIR
        array_each = described_class::ARRAY_EACH
        counting_hash_each_pair = double("HASH_EACH_PAIR")
        counting_array_each = double("ARRAY_EACH")
        allow(counting_hash_each_pair).to receive(:bind) do |hash|
          hash_count += 1
          hash_each_pair.bind(hash)
        end
        allow(counting_array_each).to receive(:bind) do |array|
          array_count += 1
          array_each.bind(array)
        end
        stub_const("#{described_class}::HASH_EACH_PAIR", counting_hash_each_pair)
        stub_const("#{described_class}::ARRAY_EACH", counting_array_each)

        build

        hashes = 0
        arrays = 0
        pending = [payload]
        until pending.empty?
          value = pending.shift
          if value.is_a?(Hash)
            hashes += 1
            pending.concat(value.values)
          elsif value.is_a?(Array)
            arrays += 1
            pending.concat(value)
          end
        end
        expect(hash_count).to eq hashes
        expect(array_count).to eq arrays
      end
    end

    context "with Arrays nested 5,000 levels deep in a captured value" do
      let(:nested) { (1..5_000).reduce([]) { |inner, _| [inner] } }
      let(:payload) { return_payload({type: "Custom", data: nested}) }

      it "encodes them on a new thread as JSON.dump does" do
        expected = Thread.new { JSON.dump(payload) }.value
        encoded = Thread.new { emit(builder.build(payload)[0]) }.value

        expect(encoded).to eq expected
      end
    end

    describe "primitive registration" do
      let(:payload) do
        return_payload(array_value([
          string_value("a" * 173),
          string_value("a" * 172),
          string_value("\u00e9" * 150),
        ]))
      end

      it "registers primitives over 200 bytes, measured in bytes" do
        expect(step1_candidates.map { |candidate| candidate.node.size }).to eq [201, 328]
      end

      it "records the primitive's position, depth and ordinal" do
        candidate = step1_candidates.first
        elements = collections.find(&:element_member).element_container

        expect(candidate.kind).to eq :primitive
        expect(candidate.parent).to equal elements
        expect(candidate.index).to eq 0
        expect(candidate.depth).to eq 3
        expect(candidate.last_ordinal).to eq candidate.ordinal
        expect(candidate.element_container).to be nil
        expect(candidate.element_count).to eq 0
        expect(candidate.cut_start_ordinal).to be nil
        expect(candidate.not_captured_reason).to be nil
        expect(candidate.reason_member_index).to be nil
        expect(candidate.size_member_index).to be nil
      end
    end

    describe "collection registration" do
      let(:payload) do
        snapshot_payload(captures: {
          entry: {arguments: (1..21).map { |i| [:"arg#{i}", {type: "Integer", value: i.to_s}] }.to_h},
          return: {
            arguments: {
              "@return": {
                type: "Hash",
                entries: (1..21).map { |i| [{type: "Integer", value: i.to_s}, {type: "Integer", value: i.to_s}] },
                size: 21,
                notCapturedReason: :collectionSize,
              },
              fields: {type: "Obj", fields: (1..21).map { |i| [:"@f#{i}", {type: "Integer", value: i.to_s}] }.to_h},
              list: array_value((1..21).map { |i| {type: "Integer", value: i.to_s} }),
            },
            throwable: {type: "E", message: "m", stacktrace: [{fileName: "f", function: "g", lineNumber: 1}] * 21},
          },
        })
      end

      include_examples "encodes as JSON.dump"

      it "assigns pre-order ordinals with each range closed by last_ordinal" do
        entry_set, entry_arguments = collections.min_by(2, &:ordinal)
        expect(entry_set.ordinal).to eq 0
        expect(entry_arguments.ordinal).to eq 1
        expect(entry_arguments.last_ordinal).to eq 22
        expect(entry_set.last_ordinal).to eq 22
        return_set = collections.find { |collection| collection.depth == 0 && collection.ordinal > 0 }
        expect(return_set.ordinal).to eq 23
        expect(return_set.last_ordinal).to eq collections.map(&:last_ordinal).max
      end

      it "registers capture sets with their member count and no cut start" do
        return_set = collections.find { |collection| collection.depth == 0 && collection.ordinal > 0 }
        expect(return_set.node).to be_a(Datadog::DI::SnapshotEncoder::ObjectNode)
        expect(return_set.element_member).to be nil
        expect(return_set.element_container).to be nil
        expect(return_set.element_count).to eq 2
        expect(return_set.cut_start_ordinal).to be nil
        expect(step2_candidates).not_to include(return_set)
      end

      it "registers a variable map as its own element container with the cut start of variable 21" do
        entry_arguments = collections.find { |collection| collection.ordinal == 1 }
        expect(entry_arguments.depth).to eq 1
        expect(entry_arguments.element_container).to equal entry_arguments.node
        expect(entry_arguments.element_count).to eq 21
        expect(entry_arguments.cut_start_ordinal).to eq 22
        expect(entry_arguments.reason_member_index).to be nil
        expect(step2_candidates).to include(entry_arguments)
      end

      it "registers value collections of each element member with their element container and markers" do
        by_member = collections.select(&:element_member).map { |collection| [collection.element_member, collection] }.to_h

        entries = by_member.fetch("entries")
        expect(entries.element_container).to be_a(Datadog::DI::SnapshotEncoder::ArrayNode)
        expect(entries.node.children[entries.node.member_names.index("entries")]).to equal entries.element_container
        expect(entries.element_count).to eq 21
        expect(entries.cut_start_ordinal).to eq entries.ordinal + 1 + 20 * 2
        expect(entries.not_captured_reason).to eq "collectionSize"
        expect(entries.reason_member_index).to eq 3
        expect(entries.size_member_index).to eq 2

        fields = by_member.fetch("fields")
        expect(fields.element_container).to be_a(Datadog::DI::SnapshotEncoder::ObjectNode)
        expect(fields.cut_start_ordinal).to eq fields.ordinal + 21
        expect(fields.not_captured_reason).to be nil
        expect(fields.reason_member_index).to be nil
        expect(fields.size_member_index).to be nil

        elements = by_member.fetch("elements")
        expect(elements.cut_start_ordinal).to eq elements.ordinal + 21
        expect(elements.last_ordinal).to eq elements.ordinal + 21

        stacktrace = by_member.fetch("stacktrace")
        expect(stacktrace.depth).to eq 1
        expect(stacktrace.element_count).to eq 21
        expect(stacktrace.cut_start_ordinal).to eq stacktrace.ordinal + 21

        expect(step2_candidates.map(&:element_member)).to contain_exactly(nil, "entries", "fields", "elements", "stacktrace")
      end
    end

    context "with exactly 20 elements" do
      let(:payload) { return_payload(array_value([{type: "Integer", value: "1"}] * 20)) }

      it "registers the collection without a cut start" do
        expect(collections.find(&:element_member).cut_start_ordinal).to be nil
        expect(step2_candidates).to be_empty
      end
    end

    context "with collections inside an entries pair and inside an elements Array" do
      let(:payload) do
        return_payload(array_value([
          {type: "Hash", entries: [[{type: "Array", elements: []}, {type: "Array", elements: []}]]},
          {type: "Array", elements: [{type: "Array", elements: []}]},
        ]))
      end

      it "gives collections at the same collection depth the same depth" do
        innermost = collections.select { |collection| collection.depth == 4 }
        expect(innermost.length).to eq 3
      end
    end

    context "with more than 20 members in every container" do
      let(:payload) do
        return_payload(array_value((1..25).map do |i|
          {type: "Obj", fields: (1..25).map { |j| [:"@f#{j}", string_value("v" * (i + j))] }.to_h}
        end))
      end

      it "records exact prefix sizes" do
        expect_exact_sizes(root)
      end
    end
  end
end
