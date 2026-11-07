require "datadog/di/spec_helper"
require_relative "snapshot_encoder_helpers"

RSpec.describe Datadog::DI::SnapshotEncoder do
  include SnapshotEncoderHelpers

  describe "constants" do
    it "holds the JSON encoding of every listed member name, frozen" do
      expect(described_class::MEMBER_NAME_JSON).to be_frozen
      expect(described_class::MEMBER_NAME_JSON.keys).to include("type", "notCapturedReason", "@return", "dd.trace_id")
      described_class::MEMBER_NAME_JSON.each do |name, name_json|
        expect(name_json).to eq JSON.dump(name)
        expect(name).to be_frozen
        expect(name_json).to be_frozen
      end
    end

    it "holds the marker encodings, frozen" do
      expect(described_class::PLACEHOLDER_JSON).to eq '{"pruned":true}'
      expect(described_class::PLACEHOLDER_JSON).to be_frozen
      expect(described_class::PAYLOAD_TOO_LARGE_JSON).to eq '"payloadTooLarge"'
      expect(described_class::PAYLOAD_TOO_LARGE_JSON).to be_frozen
    end

    it "holds the step thresholds" do
      expect(described_class::PRIMITIVE_SIZE_LIMIT).to eq 200
      expect(described_class::KEPT_ELEMENT_COUNT).to eq 20
    end
  end

  describe ".encode" do
    subject(:result) { described_class.encode(payload, cap) }

    let(:cap) { 1_044_480 }

    context "with a payload within the cap" do
      let(:payload) do
        return_payload(array_value([string_value("caf\u00e9"), {type: "Integer", value: "1"}]), entry_arguments: {a: string_value("x")})
      end

      it "returns the bytes of JSON.dump, unpruned" do
        expect(result.encoded).to eq JSON.dump(payload)
        expect(result.encoded.encoding).to eq Encoding::UTF_8
        expect(result.pruned?).to be false
        expect(result.bytes).to eq JSON.dump(payload).bytesize
        expect([result.replaced_primitives, result.cut_collections, result.replaced_collections]).to eq [0, 0, 0]
      end
    end

    context "with an ASCII-only payload" do
      let(:payload) { snapshot_payload(captures: {}) }

      it "returns a UTF-8 string" do
        expect(result.encoded.encoding).to eq Encoding::UTF_8
      end
    end

    context "with a payload of exactly the cap" do
      let(:payload) { return_payload(array_value([string_value("x" * 300)] * 4)) }
      let(:cap) { JSON.dump(payload).bytesize }

      it "sends the payload unchanged" do
        expect(result.encoded).to eq JSON.dump(payload)
        expect(result.pruned?).to be false
        expect(result.replaced_primitives).to eq 0
      end

      context "and a cap one byte larger" do
        let(:cap) { JSON.dump(payload).bytesize + 1 }

        it "sends the payload unchanged" do
          expect(result.encoded).to eq JSON.dump(payload)
          expect(result.pruned?).to be false
        end
      end
    end

    context "with a payload one byte over the cap" do
      let(:payload) { return_payload(array_value([string_value("a" * 300), string_value("b" * 301)])) }
      let(:cap) { JSON.dump(payload).bytesize - 1 }

      it "returns the pruned JSON text" do
        expected = JSON.dump(return_payload(array_value([string_value("a" * 300), {pruned: true}])))
        expect(result.encoded).to eq expected
        expect(result.encoded.bytesize).to be <= cap
        expect(result.pruned?).to be true
        expect(result.bytes).to eq JSON.dump(payload).bytesize
        expect([result.replaced_primitives, result.cut_collections, result.replaced_collections]).to eq [1, 0, 0]
      end
    end

    context "with a payload pruned by every step" do
      let(:payload) do
        return_payload(array_value([string_value("x" * 300)] + (1..30).map { |i| array_value([{type: "I", value: i}]) }))
      end
      let(:cap) { 1_500 }

      it "counts the changes of each step and keeps the unpruned size" do
        expect(result.pruned?).to be true
        expect(result.encoded.bytesize).to be <= cap
        expect(result.replaced_primitives).to eq 1
        expect(result.cut_collections).to eq 1
        expect(result.replaced_collections).to be > 0
        expect(result.bytes).to eq JSON.dump(payload).bytesize
      end
    end

    context "when the envelope with every capture set replaced exceeds the cap" do
      let(:payload) do
        snapshot_payload(captures: {entry: {arguments: {a: string_value("x" * 300)}}, return: {arguments: {}, throwable: nil}})
      end
      let(:pruned_size) do
        JSON.dump(snapshot_payload(captures: {entry: {pruned: true}, return: {pruned: true}})).bytesize
      end

      context "by one byte" do
        let(:cap) { pruned_size - 1 }

        it "drops the payload" do
          expect(result.encoded).to be nil
          expect(result.pruned?).to be false
          expect(result.bytes).to eq JSON.dump(payload).bytesize
          expect(result.replaced_collections).to eq 4
        end
      end

      context "by zero bytes" do
        let(:cap) { pruned_size }

        it "sends the payload with every capture set replaced" do
          expect(result.encoded).to eq JSON.dump(snapshot_payload(captures: {entry: {pruned: true}, return: {pruned: true}}))
          expect(result.pruned?).to be true
        end
      end
    end

    context "when pruning" do
      let(:payload) { return_payload(array_value([string_value("a" * 300), {type: "Custom", data: {k: [1, nil]}}])) }
      let(:cap) { JSON.dump(payload).bytesize - 1 }

      it "writes no collection JSON before pruning ends and holds complete JSON in every fragment" do
        pruned = false
        allow_any_instance_of(described_class::Emitter).to receive(:emit).and_wrap_original do |original, root|
          expect(pruned).to be true
          original.call(root)
        end
        allow_any_instance_of(described_class::Pruner).to receive(:prune).and_wrap_original do |original|
          fragments = container_nodes(original.receiver.root).flat_map(&:children)
            .grep(described_class::FragmentNode).map(&:fragment)
          fragments.each { |fragment| expect { JSON.parse(fragment) }.not_to raise_error }
          counts = original.call
          pruned = true
          counts
        end

        expect(result.pruned?).to be true
      end
    end

    context "at default capture settings with 100 arrays of 100 strings of 300 characters" do
      let(:truncated_string) { {type: "String", value: "x" * 255, truncated: true, size: 300} }
      let(:payload) { return_payload(array_value(Array.new(100) { array_value(Array.new(100) { truncated_string }, size: 100) })) }

      it "fits the payload with step 1 alone, keeping the first inner arrays" do
        expect(result.encoded.bytesize).to be <= cap
        expect([result.cut_collections, result.replaced_collections]).to eq [0, 0]

        inner_arrays = JSON.parse(result.encoded).dig("debugger", "snapshot", "captures", "return", "arguments", "@return", "elements")
        expect(inner_arrays.first["elements"]).not_to include("pruned" => true)
        expect(inner_arrays.last["elements"]).to all(eq("pruned" => true))
      end
    end

    context "with a string tagged UTF-8 that has invalid bytes" do
      let(:payload) { return_payload(string_value((+"\xff").force_encoding(Encoding::UTF_8))) }

      it "raises the error class JSON.dump raises for the payload" do
        expected_class = begin
          JSON.dump(payload)
        rescue => exc
          exc.class
        end
        expect { result }.to raise_error(expected_class)
      end
    end

    context "with a BINARY string with bytes above 0x7F" do
      let(:payload) { return_payload(string_value("\xff".b)) }

      it "raises the error class JSON.dump raises for the payload" do
        expected_class = begin
          JSON.dump(payload)
        rescue => exc
          exc.class
        end
        expect(expected_class).to be < Exception
        expect { result }.to raise_error(expected_class)
      end
    end
  end
end
