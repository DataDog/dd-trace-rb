require "datadog/di/spec_helper"
require "datadog/di/snapshot_pruner/parser"

RSpec.describe Datadog::DI::SnapshotPruner::Parser do
  di_test

  subject(:parser) { described_class.new }

  def object_text(json, node)
    json.byteslice(node.start_offset, node.size)
  end

  describe "#parse" do
    context "with nested objects and arrays" do
      let(:json) { '{"a":{"b":{}},"c":[{"d":1},{"e":[2,{}]}],"f":"g"}' }

      it "builds one node per object with byte ranges and levels" do
        root = parser.parse(json)

        expect(root.start_offset).to eq 0
        expect(root.end_offset).to eq json.bytesize
        expect(root.level).to eq 0
        expect(root.parent).to be_nil

        a, d, e = root.children
        expect(root.children.size).to eq 3
        expect(object_text(json, a)).to eq '{"b":{}}'
        expect(object_text(json, d)).to eq '{"d":1}'
        expect(object_text(json, e)).to eq '{"e":[2,{}]}'
        expect([a, d, e].map(&:level)).to eq [1, 1, 1]
        expect([a, d, e].map(&:parent)).to all(be(root))

        b = a.children.first
        expect(object_text(json, b)).to eq "{}"
        expect(b.level).to eq 2
        expect(b.leaf?).to be true
        expect(object_text(json, e.children.first)).to eq "{}"
      end
    end

    context "with multibyte strings" do
      let(:json) { "{\"a\":\"\u20ac\u20ac\",\"b\":{\"c\":\"\u20ac\"}}" }

      it "records byte offsets" do
        b = parser.parse(json).children.first

        expect(object_text(json, b)).to eq "{\"c\":\"\u20ac\"}"
        expect(b.size).to eq "{\"c\":\"\u20ac\"}".bytesize
      end
    end

    context "with braces, quotes and backslashes inside strings" do
      let(:json) { '{"a":"{\\"}\\\\","b":{"c":"}{"},"d\\"{":{}}' }

      it "creates nodes only for objects" do
        root = parser.parse(json)

        expect(root.end_offset).to eq json.bytesize
        expect(root.children.map { |child| object_text(json, child) }).to eq ['{"c":"}{"}', "{}"]
      end
    end

    context "with a notCapturedReason member" do
      let(:json) { '{"a":{"type":"X","notCapturedReason":"fieldCount"},"b":{"notCapturedReason" : "depth"}}' }

      it "flags the object, and flags the depth value" do
        a, b = parser.parse(json).children

        expect(a.not_captured?).to be true
        expect(a.not_captured_depth?).to be false
        expect(b.not_captured?).to be true
        expect(b.not_captured_depth?).to be true
      end
    end

    context "with a notCapturedReason value starting with depth" do
      let(:json) { '{"a":{"notCapturedReason":"depthLimit"}}' }

      it "flags the object as not captured only" do
        a = parser.parse(json).children.first

        expect(a.not_captured?).to be true
        expect(a.not_captured_depth?).to be false
      end
    end

    context "with a string value equal to notCapturedReason" do
      let(:json) { '{"a":{"value":"notCapturedReason"},"b":{"value":"depth"},"c":{"notCapturedReasonX":"depth"}}' }

      it "flags no object and keeps parsing" do
        root = parser.parse(json)

        expect(root.end_offset).to eq json.bytesize
        expect(root.children.size).to eq 3
        expect(root.children.map(&:not_captured?)).to eq [false, false, false]
        expect(root.children.map(&:not_captured_depth?)).to eq [false, false, false]
      end
    end

    context "with data after the root object" do
      let(:json) { '{"a":{}}{"b":{}}' }

      it "stops at the end of the root object" do
        root = parser.parse(json)

        expect(root.end_offset).to eq 8
        expect(root.children.size).to eq 1
      end
    end

    context "when the root object is not closed" do
      it "returns nil" do
        expect(parser.parse('{"a":{"b":{}}')).to be_nil
      end
    end

    context "when a string is not closed" do
      it "returns nil" do
        expect(parser.parse('{"a":"unterminated')).to be_nil
      end
    end

    context "when a closing brace precedes every opening brace" do
      it "returns nil" do
        expect(parser.parse('}{"a":1}')).to be_nil
      end
    end

    context "when the document holds no object" do
      it "returns nil" do
        expect(parser.parse('["a",1]')).to be_nil
      end
    end
  end
end
