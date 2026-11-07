require "datadog/di/spec_helper"
require_relative "../snapshot_encoder_helpers"

RSpec.describe Datadog::DI::SnapshotEncoder::Pruner do
  include SnapshotEncoderHelpers

  let(:placeholder) { {"pruned" => true} }

  # Prunes the encoded tree of +payload+ to +cap+ and returns the root
  # and the step counts.
  def prune(payload, cap)
    root, step1_candidates, step2_candidates, collections = build_tree(payload)
    counts = described_class.new(
      root: root, step1_candidates: step1_candidates, step2_candidates: step2_candidates,
      collections: collections, cap: cap,
    ).prune
    expect_exact_sizes(root)
    [root, counts]
  end

  # Prunes +payload+ to its encoded size minus +excess+ bytes.
  def prune_by(payload, excess)
    prune(payload, JSON.dump(payload).bytesize - excess)
  end

  def parsed_return(root)
    JSON.parse(emit(root)).dig("debugger", "snapshot", "captures", "return", "arguments", "@return")
  end

  def integer_value(number)
    {type: "Integer", value: number.to_s}
  end

  def integers(count)
    (1..count).map { |i| integer_value(i) }
  end

  describe "#prune" do
    it "changes nothing when the payload fits" do
      payload = return_payload(array_value([string_value("x" * 300)]))
      root, counts = prune(payload, JSON.dump(payload).bytesize)

      expect(emit(root)).to eq JSON.dump(payload)
      expect(counts).to eq(replaced_primitives: 0, cut_collections: 0, replaced_collections: 0)
    end

    describe "step 1" do
      it "replaces the largest primitive first" do
        payload = return_payload(array_value([string_value("a" * 300), string_value("b" * 500), string_value("c" * 400)]))
        root, counts = prune_by(payload, 1)

        expect(parsed_return(root)["elements"].map { |element| element == placeholder })
          .to eq [false, true, false]
        expect(counts).to eq(replaced_primitives: 1, cut_collections: 0, replaced_collections: 0)
      end

      it "replaces the primitive with the greater ordinal first among equal sizes" do
        payload = return_payload(array_value([string_value("a" * 300), string_value("b" * 300)]))
        root, = prune_by(payload, 1)

        expect(parsed_return(root)["elements"]).to eq [JSON.parse(JSON.dump(string_value("a" * 300))), placeholder]
      end

      it "stops as soon as the payload fits" do
        payload = return_payload(array_value([string_value("a" * 300), string_value("b" * 500), string_value("c" * 400)]))
        saved_by_largest = JSON.dump(string_value("b" * 500)).bytesize - placeholder.to_json.bytesize

        _, counts = prune_by(payload, saved_by_largest)
        expect(counts[:replaced_primitives]).to eq 1

        _, counts = prune_by(payload, saved_by_largest + 1)
        expect(counts[:replaced_primitives]).to eq 2
      end

      it "never replaces a primitive of 200 bytes" do
        payload = return_payload(array_value([string_value("a" * 172)] * 3))
        root, counts = prune_by(payload, 1)

        expect(counts[:replaced_primitives]).to eq 0
        expect(counts[:replaced_collections]).to be > 0
        expect(root.size).to be <= JSON.dump(payload).bytesize - 1
      end

      it "replaces a pair key and a throwable stack frame like any primitive" do
        payload = snapshot_payload(captures: {
          return: {
            arguments: {"@return": {type: "Hash", entries: [[string_value("k" * 400), integer_value(1)]]}},
            throwable: {type: "E", message: "m", stacktrace: [{fileName: "f" * 300, function: "g", lineNumber: 1}]},
          },
        })
        root, counts = prune_by(payload, 500)

        captures = JSON.parse(emit(root)).dig("debugger", "snapshot", "captures", "return")
        expect(captures.dig("arguments", "@return", "entries")).to eq [[placeholder, {"type" => "Integer", "value" => "1"}]]
        expect(captures.dig("throwable", "stacktrace")).to eq [placeholder]
        expect(counts[:replaced_primitives]).to eq 2
      end
    end

    describe "step 2" do
      it "runs only after step 1 has no candidates left" do
        payload = return_payload(array_value(integers(24) + [string_value("x" * 300)]))
        # Step 1 saves 313 bytes and the cut saves 96 more.
        root, counts = prune_by(payload, 400)

        expect(counts).to eq(replaced_primitives: 1, cut_collections: 1, replaced_collections: 0)
        expect(parsed_return(root)["elements"].length).to eq 20
      end

      it "cuts the largest collection to its first 20 elements" do
        payload = return_payload(nil, entry_arguments: {
          small: array_value(integers(25)),
          large: array_value((1..25).map { |i| string_value("v#{i}" * 10) }),
        })
        root, counts = prune_by(payload, 1)

        arguments = JSON.parse(emit(root)).dig("debugger", "snapshot", "captures", "entry", "arguments")
        expect(arguments.dig("large", "elements").length).to eq 20
        expect(arguments.dig("small", "elements").length).to eq 25
        expect(counts[:cut_collections]).to eq 1
      end

      it "orders the collections by their size after step 1" do
        first = array_value(integers(24) + [string_value("x" * 3_000)])
        second = array_value((1..25).map { |i| string_value("s#{i}" * 30) })
        payload = return_payload(nil, entry_arguments: {first: first, second: second})
        expect(JSON.dump(first).bytesize).to be > JSON.dump(second).bytesize
        after_step1 = JSON.dump(payload).bytesize - (JSON.dump(string_value("x" * 3_000)).bytesize - 15)

        root, counts = prune(payload, after_step1 - 1)

        arguments = JSON.parse(emit(root)).dig("debugger", "snapshot", "captures", "entry", "arguments")
        expect(arguments.dig("second", "elements").length).to eq 20
        expect(arguments.dig("first", "elements").length).to eq 25
        expect(counts).to eq(replaced_primitives: 1, cut_collections: 1, replaced_collections: 0)
      end

      it "cuts the collection with the greater ordinal first among equal sizes" do
        payload = return_payload(nil, entry_arguments: {a: array_value(integers(25)), b: array_value(integers(25))})
        root, = prune_by(payload, 1)

        arguments = JSON.parse(emit(root)).dig("debugger", "snapshot", "captures", "entry", "arguments")
        expect(arguments.dig("a", "elements").length).to eq 25
        expect(arguments.dig("b", "elements").length).to eq 20
      end

      it "never cuts a collection of 20 elements" do
        payload = return_payload(array_value(integers(20)))
        _, counts = prune_by(payload, 1)

        expect(counts[:cut_collections]).to eq 0
        expect(counts[:replaced_collections]).to be > 0
      end

      it "skips collections inside a cut-away element, at both ends of the removed range and inside it" do
        inner = (1..24).map { array_value(integers(25)) } + [array_value([])]
        payload = return_payload(array_value(inner))
        _, counts = prune(payload, 0)

        # The outer array and its 20 kept inner arrays.
        expect(counts[:cut_collections]).to eq 21
        # Every collection outside the removed range: the two capture sets,
        # the two variable maps, the outer array and the 20 kept inner arrays.
        expect(counts[:replaced_collections]).to eq 25
      end

      it "stops as soon as the payload fits" do
        payload = return_payload(nil, entry_arguments: {a: array_value(integers(25)), b: array_value(integers(25))})
        _, counts = prune_by(payload, 1)

        expect(counts[:cut_collections]).to eq 1
      end

      describe "markers" do
        def cut_return_json(value)
          JSON.parse(emit(prune_by(return_payload(value), 1)[0])).dig(
            "debugger", "snapshot", "captures", "return", "arguments", "@return",
          )
        end

        def kept_json(elements)
          elements.first(20).map { |element| JSON.dump(element) }.join(",")
        end

        it "appends the reason and the pre-cut size to an elements collection" do
          emitted = emit(prune_by(return_payload(array_value(integers(25))), 1)[0])

          expect(emitted).to include(
            "\"@return\":{\"type\":\"Array\",\"elements\":[#{kept_json(integers(25))}]," \
            "\"notCapturedReason\":\"payloadTooLarge\",\"size\":25}",
          )
        end

        it "appends the reason and the pre-cut size to an entries collection" do
          pairs = (1..25).map { |i| [integer_value(i), integer_value(i)] }
          emitted = emit(prune_by(return_payload({type: "Hash", entries: pairs}), 1)[0])

          expect(emitted).to include(
            "\"@return\":{\"type\":\"Hash\",\"entries\":[#{kept_json(pairs)}]," \
            "\"notCapturedReason\":\"payloadTooLarge\",\"size\":25}",
          )
        end

        it "appends only the reason to a fields collection" do
          fields = (1..25).map { |i| [:"@f#{i}", integer_value(i)] }.to_h
          emitted = emit(prune_by(return_payload({type: "Obj", fields: fields}), 1)[0])

          kept = fields.first(20).map { |name, value| "\"#{name}\":#{JSON.dump(value)}" }.join(",")
          expect(emitted).to include(
            "\"@return\":{\"type\":\"Obj\",\"fields\":{#{kept}},\"notCapturedReason\":\"payloadTooLarge\"}",
          )
        end

        it "appends only the reason to a stacktrace collection" do
          frames = (1..25).map { |i| {fileName: "f", function: "g", lineNumber: i} }
          payload = snapshot_payload(captures: {return: {arguments: {}, throwable: {type: "E", message: "m", stacktrace: frames}}})
          emitted = emit(prune_by(payload, 1)[0])

          expect(emitted).to include(
            "\"throwable\":{\"type\":\"E\",\"message\":\"m\",\"stacktrace\":[#{kept_json(frames)}]," \
            "\"notCapturedReason\":\"payloadTooLarge\"}",
          )
        end

        it "appends only the reason to a collection that has a size" do
          emitted = emit(prune_by(return_payload(array_value(integers(25), size: 30)), 1)[0])

          expect(emitted).to include(
            "\"@return\":{\"type\":\"Array\",\"elements\":[#{kept_json(integers(25))}],\"size\":30," \
            "\"notCapturedReason\":\"payloadTooLarge\"}",
          )
        end

        it "keeps a timeout reason and adds no size" do
          emitted = emit(prune_by(return_payload(array_value(integers(25), notCapturedReason: "timeout")), 1)[0])

          expect(emitted).to include(
            "\"@return\":{\"type\":\"Array\",\"elements\":[#{kept_json(integers(25))}],\"notCapturedReason\":\"timeout\"}",
          )
        end

        it "recognizes a String-keyed reason and compares its value with to_s" do
          value = {"type" => "Array", "elements" => integers(25), "notCapturedReason" => :timeout}
          expect(cut_return_json(value)).to eq(
            "type" => "Array", "elements" => JSON.parse(JSON.dump(integers(20))), "notCapturedReason" => "timeout",
          )
        end

        %w[collectionSize fieldCount depth redactedIdent redactedType customReason].each do |reason|
          it "replaces the #{reason} reason and keeps the existing size" do
            emitted = emit(prune_by(return_payload(array_value(integers(25), notCapturedReason: reason, size: 40)), 1)[0])

            expect(emitted).to include(
              "\"@return\":{\"type\":\"Array\",\"elements\":[#{kept_json(integers(25))}]," \
              "\"notCapturedReason\":\"payloadTooLarge\",\"size\":40}",
            )
          end
        end

        it "replaces a reason whose value is nil" do
          expect(cut_return_json(array_value(integers(25), notCapturedReason: nil))["notCapturedReason"])
            .to eq "payloadTooLarge"
        end

        it "keeps the first 20 variables of a variable map without a marker" do
          arguments = (1..25).map { |i| [:"arg#{i}", integer_value(i)] }.to_h
          root, counts = prune_by(return_payload(nil, entry_arguments: arguments), 1)

          emitted_arguments = JSON.parse(emit(root)).dig("debugger", "snapshot", "captures", "entry", "arguments")
          expect(emitted_arguments.keys).to eq (1..20).map { |i| "arg#{i}" }
          expect(counts[:cut_collections]).to eq 1
        end

        it "keeps the sizes exact when a cut makes a collection larger" do
          payload = return_payload(array_value([{type: "I", value: 1}] * 21))
          before = JSON.dump(payload).bytesize

          root, counts = prune(payload, before - 1)

          expect(counts[:cut_collections]).to eq 1
          expect(counts[:replaced_collections]).to be > 0
          expect(root.size).to eq emit(root).bytesize
        end
      end
    end

    describe "step 3" do
      def replaced_member_names(payload, cap)
        names = []
        allow_any_instance_of(Datadog::DI::SnapshotEncoder::ObjectNode).to receive(:replace_child)
          .and_wrap_original do |original, index, node|
            names << original.receiver.member_names[index]
            original.call(index, node)
          end
        _, counts = prune(payload, cap)
        [names, counts]
      end

      it "replaces the deepest collections first, then greater ordinals, ending with capture sets" do
        payload = snapshot_payload(captures: {
          entry: {arguments: {a: array_value([])}},
          return: {
            arguments: {"@return": array_value([])},
            throwable: {type: "E", message: "m", stacktrace: []},
          },
        })
        names, counts = replaced_member_names(payload, 0)

        expect(names).to eq ["@return", "a", "throwable", "arguments", "arguments", "return", "entry"]
        expect(counts).to eq(replaced_primitives: 0, cut_collections: 0, replaced_collections: 7)
      end

      it "replaces cut collections" do
        payload = return_payload(array_value(integers(25)))
        names, counts = replaced_member_names(payload, 0)

        expect(counts[:cut_collections]).to eq 1
        expect(names.first).to eq "@return"
      end

      it "replaces a collection smaller than the placeholder" do
        payload = snapshot_payload(captures: {lines: {3 => {captureExpressions: {}}}})
        names, = replaced_member_names(payload, JSON.dump(payload).bytesize - 1)

        # The placeholder is larger than the empty map, so the capture set
        # is replaced next.
        expect(names).to eq ["captureExpressions", "3"]
      end

      it "stops as soon as the payload fits" do
        payload = return_payload(nil, entry_arguments: {a: array_value([integer_value(1)]), b: array_value([integer_value(2)])})
        names, = replaced_member_names(payload, JSON.dump(payload).bytesize - 1)

        expect(names).to eq ["b"]
      end

      it "keeps the captures and lines Hashes and the envelope stack" do
        payload = snapshot_payload(captures: {lines: {3 => {locals: {a: array_value([])}}}})
        root, = prune(payload, 0)

        emitted = JSON.parse(emit(root))
        expect(emitted.dig("debugger", "snapshot", "captures")).to eq("lines" => {"3" => placeholder})
        expect(emitted.dig("debugger", "snapshot", "stack")).to eq JSON.parse(JSON.dump(payload)).dig("debugger", "snapshot", "stack")
      end
    end
  end

  describe "removed ranges" do
    subject(:pruner) do
      described_class.new(root: Datadog::DI::SnapshotEncoder::ObjectNode.new, step1_candidates: [],
        step2_candidates: [], collections: [], cap: 0)
    end

    def removed(ordinals)
      ordinals.select { |ordinal| pruner.send(:removed?, ordinal) }
    end

    it "tests both range ends and the inside" do
      pruner.send(:record_removed_range, 10, 20)

      expect(removed([9, 10, 15, 20, 21])).to eq [10, 15, 20]
    end

    it "keeps ranges recorded in descending order sorted" do
      pruner.send(:record_removed_range, 50, 60)
      pruner.send(:record_removed_range, 30, 40)
      pruner.send(:record_removed_range, 10, 20)

      expect(removed([5, 10, 20, 25, 30, 40, 45, 50, 60, 61])).to eq [10, 20, 30, 40, 50, 60]
    end

    it "keeps ranges recorded in mixed order sorted" do
      pruner.send(:record_removed_range, 30, 40)
      pruner.send(:record_removed_range, 70, 80)
      pruner.send(:record_removed_range, 10, 20)
      pruner.send(:record_removed_range, 50, 55)

      expect(removed([10, 21, 35, 45, 52, 56, 75, 81])).to eq [10, 35, 52, 75]
    end

    it "removes nothing without ranges" do
      expect(removed([0, 1])).to be_empty
    end
  end
end
