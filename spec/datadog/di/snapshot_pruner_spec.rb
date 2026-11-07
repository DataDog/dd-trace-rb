require "datadog/di/spec_helper"
require "json"
require "datadog/di/snapshot_pruner"

RSpec.describe Datadog::DI::SnapshotPruner do
  di_test

  subject(:pruner) { described_class.new }

  # Encodes a method probe snapshot. By default the return capture set
  # holds +arguments+: the arguments map is at level 5 and each captured
  # value at level 6.
  def snapshot_json(arguments: {}, captures: {return: {arguments: arguments}}, stack: [])
    JSON.dump(
      service: "pruner-spec",
      debugger: {
        snapshot: {
          stack: stack,
          captures: captures,
        },
      },
      message: "pruner spec",
    )
  end

  def string_value(length, char: "x")
    {type: "String", value: char * length}
  end

  def encoded_size(value)
    JSON.dump(value).bytesize
  end

  def pruned_arguments(json)
    JSON.parse(json).dig("debugger", "snapshot", "captures", "return", "arguments")
  end

  let(:marker_size) { described_class::PRUNED_MARKER.bytesize }

  describe "#prune" do
    context "when the snapshot is within the limit" do
      let(:json) { snapshot_json(arguments: {a: string_value(1_000)}) }

      it "returns the snapshot itself" do
        expect(pruner.prune(json, max_size: json.bytesize)).to be(json)
      end
    end

    context "when same-level leaves differ in size" do
      let(:json) { snapshot_json(arguments: {small: string_value(100), large: string_value(300)}) }

      it "replaces the largest leaf" do
        result = pruner.prune(json, max_size: json.bytesize - 10)

        expect(pruned_arguments(result)).to eq(
          "small" => {"type" => "String", "value" => "x" * 100},
          "large" => {"pruned" => true},
        )
        expect(result.bytesize).to be < json.bytesize - 10
      end
    end

    context "when a deeper leaf is smaller than a shallower one" do
      let(:json) do
        snapshot_json(arguments: {
          shallow: string_value(500),
          nested: {type: "Hash", fields: {inner: string_value(100)}},
        })
      end

      it "replaces the deeper leaf" do
        result = pruner.prune(json, max_size: json.bytesize - 10)

        expect(pruned_arguments(result)).to eq(
          "shallow" => {"type" => "String", "value" => "x" * 500},
          "nested" => {"type" => "Hash", "fields" => {"inner" => {"pruned" => true}}},
        )
      end
    end

    context "when an object is truncated for depth" do
      let(:json) do
        snapshot_json(arguments: {
          truncated: {type: "Object", notCapturedReason: "depth"},
          nested: {type: "Hash", fields: {inner: string_value(500)}},
        })
      end

      it "replaces the truncated object before deeper and larger objects" do
        result = pruner.prune(json, max_size: json.bytesize - 10)

        expect(pruned_arguments(result)).to eq(
          "truncated" => {"pruned" => true},
          "nested" => {"type" => "Hash", "fields" => {"inner" => {"type" => "String", "value" => "x" * 500}}},
        )
      end
    end

    context "when an object carries a notCapturedReason other than depth" do
      let(:json) do
        snapshot_json(arguments: {
          redacted: {type: "Secret", notCapturedReason: "redactedIdent"},
          large: string_value(500),
        })
      end

      it "replaces it before larger objects at its level" do
        result = pruner.prune(json, max_size: json.bytesize - 10)

        expect(pruned_arguments(result)).to eq(
          "redacted" => {"pruned" => true},
          "large" => {"type" => "String", "value" => "x" * 500},
        )
      end
    end

    context "when several leaves can cover the excess" do
      let(:arguments) { (1..10).to_h { |i| [:"arg#{i}", string_value(100)] } }
      let(:json) { snapshot_json(arguments: arguments) }
      let(:leaf_saving) { encoded_size(string_value(100)) - marker_size }

      it "stops as soon as the snapshot is below the limit" do
        max_size = json.bytesize - 2 * leaf_saving - 1
        result = pruner.prune(json, max_size: max_size)

        expect(pruned_arguments(result).values.count { |value| value == {"pruned" => true} }).to eq 3
        expect(result.bytesize).to be < max_size
      end
    end

    context "when a single replacement saves exactly the excess" do
      let(:json) { snapshot_json(arguments: {large: string_value(1_000), small: string_value(50)}) }
      let(:large_saving) { encoded_size(string_value(1_000)) - marker_size }

      it "stops once the savings cover the excess exactly" do
        max_size = json.bytesize - large_saving
        result = pruner.prune(json, max_size: max_size)

        expect(pruned_arguments(result)).to eq(
          "large" => {"pruned" => true},
          "small" => {"type" => "String", "value" => "x" * 50},
        )
        expect(result.bytesize).to eq max_size
      end
    end

    context "when every child of a parent at level 6 is selected" do
      let(:children) { [string_value(200), string_value(200)] }
      let(:json) do
        snapshot_json(arguments: {
          list: {type: "Array", elements: children},
          other: string_value(50),
        })
      end
      let(:children_saving) { children.sum { |child| encoded_size(child) - marker_size } }

      it "replaces the parent whole" do
        result = pruner.prune(json, max_size: json.bytesize - children_saving - 10)

        expect(pruned_arguments(result)).to eq(
          "list" => {"pruned" => true},
          "other" => {"type" => "String", "value" => "x" * 50},
        )
        expect(result.bytesize).to be < json.bytesize - children_saving - 10
      end
    end

    context "when the candidates cannot cover the excess" do
      let(:json) { snapshot_json(arguments: {a: string_value(100)}, stack: [{fileName: "f" * 2_000}]) }

      it "replaces the level 5 arguments map, keeps the level 4 capture set, and returns a result above the limit" do
        max_size = 1_000
        result = pruner.prune(json, max_size: max_size)

        expect(JSON.parse(result).dig("debugger", "snapshot", "captures")).to eq(
          "return" => {"arguments" => {"pruned" => true}},
        )
        expect(result.bytesize).to be > max_size
      end
    end

    context "when no object is at level 5 or deeper" do
      let(:json) { snapshot_json(captures: {}, stack: [{fileName: "f" * 2_000}]) }

      it "returns the snapshot itself" do
        expect(pruner.prune(json, max_size: 1_000)).to be(json)
      end
    end

    context "when an object at level 5 or deeper is no larger than the marker" do
      let(:json) do
        snapshot_json(
          captures: {
            entry: {arguments: {}},
            return: {arguments: {a: string_value(100)}},
          },
          stack: [{fileName: "f" * 2_000}],
        )
      end

      it "keeps the object" do
        result = pruner.prune(json, max_size: 1_000)

        expect(JSON.parse(result).dig("debugger", "snapshot", "captures")).to eq(
          "entry" => {"arguments" => {}},
          "return" => {"arguments" => {"pruned" => true}},
        )
      end
    end

    context "when the only child of a captured value is an empty object" do
      let(:json) do
        snapshot_json(arguments: {
          object: {type: "Widget", fields: {}},
          large: string_value(100),
        })
      end

      it "counts the empty object toward promotion and replaces the captured value whole" do
        result = pruner.prune(json, max_size: json.bytesize - 5)

        expect(pruned_arguments(result)).to eq(
          "object" => {"pruned" => true},
          "large" => {"type" => "String", "value" => "x" * 100},
        )
      end
    end

    context "when the root object is not closed" do
      let(:json) { snapshot_json(arguments: {a: string_value(500)}).chomp("}") }

      it "raises the no closed root object error" do
        expect { pruner.prune(json, max_size: 100) }
          .to raise_error(ArgumentError, "no closed root object in the document")
      end
    end

    context "when a string is not closed" do
      let(:json) { '{"debugger":{"snapshot":{"captures":{"return":{"arguments":{"a":{"value":"' + "x" * 500 }

      it "raises the unclosed string error" do
        expect { pruner.prune(json, max_size: 100) }
          .to raise_error(ArgumentError, /\Aunclosed string starting at byte \d+\z/)
      end
    end

    context "when strings contain braces, quotes and backslashes" do
      let(:specials) { string_value(1, char: "{\"}\\{") }
      let(:json) { snapshot_json(arguments: {specials: specials, large: string_value(300), small: string_value(10)}) }

      it "keeps the object structure of the snapshot" do
        result = pruner.prune(json, max_size: json.bytesize - 10)

        expect(pruned_arguments(result)).to eq(
          "specials" => {"type" => "String", "value" => "{\"}\\{"},
          "large" => {"pruned" => true},
          "small" => {"type" => "String", "value" => "x" * 10},
        )
      end
    end

    context "when a captured string equals notCapturedReason" do
      let(:json) do
        snapshot_json(arguments: {
          lookalike: {type: "String", value: "notCapturedReason"},
          large: string_value(100),
        })
      end

      it "ranks the object by size alone and keeps parsing past it" do
        result = pruner.prune(json, max_size: json.bytesize - 10)

        expect(pruned_arguments(result)).to eq(
          "lookalike" => {"type" => "String", "value" => "notCapturedReason"},
          "large" => {"pruned" => true},
        )
      end
    end

    context "when captured strings are multibyte" do
      let(:json) do
        snapshot_json(arguments: {
          multibyte: string_value(100, char: "\u20ac"),
          ascii: string_value(200),
        })
      end

      it "ranks and limits by bytes" do
        result = pruner.prune(json, max_size: json.bytesize - 10)

        expect(pruned_arguments(result)).to eq(
          "multibyte" => {"pruned" => true},
          "ascii" => {"type" => "String", "value" => "x" * 200},
        )
        expect(result.encoding).to eq(Encoding::UTF_8)
        expect(result).to be_valid_encoding
      end
    end

    context "when a large snapshot is pruned" do
      let(:rows) do
        Array.new(20) do |row|
          {type: "Array", elements: Array.new(20) { string_value(100 + row) }}
        end
      end
      let(:json) { snapshot_json(arguments: {"@return": {type: "Array", elements: rows}}) }

      it "replaces the rows with the longest strings and keeps every other member" do
        result = pruner.prune(json, max_size: json.bytesize / 2)

        expect(result.bytesize).to be < json.bytesize / 2
        parsed = JSON.parse(result)
        original = JSON.parse(json)
        expect(parsed["service"]).to eq original["service"]
        expect(parsed["message"]).to eq original["message"]
        pruned_rows = parsed.dig("debugger", "snapshot", "captures", "return", "arguments", "@return", "elements")
        original_rows = original.dig("debugger", "snapshot", "captures", "return", "arguments", "@return", "elements")
        expect(pruned_rows.size).to eq 20
        expect(pruned_rows.last).to eq("pruned" => true)
        expect(pruned_rows.first).to eq original_rows.first
        pruned_rows.zip(original_rows).each do |pruned_row, original_row|
          next if pruned_row == {"pruned" => true}

          pruned_row["elements"].zip(original_row["elements"]).each do |pruned_value, original_value|
            expect(pruned_value).to eq(original_value).or eq("pruned" => true)
          end
        end
      end
    end
  end
end
