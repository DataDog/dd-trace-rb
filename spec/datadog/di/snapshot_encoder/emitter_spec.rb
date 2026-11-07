require "datadog/di/spec_helper"
require_relative "../snapshot_encoder_helpers"

RSpec.describe Datadog::DI::SnapshotEncoder::Emitter do
  include SnapshotEncoderHelpers

  subject(:emitter) { described_class.new }

  def fragment(text)
    Datadog::DI::SnapshotEncoder::FragmentNode.new(text)
  end

  describe "#emit" do
    it "writes a fragment node's text" do
      expect(emitter.emit(fragment("\"x\""))).to eq "\"x\""
    end

    it "writes objects and arrays in member order with their member names" do
      object = Datadog::DI::SnapshotEncoder::ObjectNode.new
      array = Datadog::DI::SnapshotEncoder::ArrayNode.new
      array.add_element(fragment("1"))
      array.add_element(Datadog::DI::SnapshotEncoder::ObjectNode.new)
      object.add_member("b", "\"b\"", array)
      object.add_member("a", "\"a\"", fragment("null"))

      expect(emitter.emit(object)).to eq "{\"b\":[1,{}],\"a\":null}"
    end

    it "returns a UTF-8 string of the root size" do
      payload = {"caf\u00e9" => ["\u00fc", 1, true]}
      root, = build_tree(payload)

      output = emitter.emit(root)

      expect(output).to eq JSON.dump(payload)
      expect(output.encoding).to eq Encoding::UTF_8
      expect(output.bytesize).to eq root.size
    end

    it "writes 10,000 nested arrays without growing the call stack" do
      root = Datadog::DI::SnapshotEncoder::ArrayNode.new
      10_000.times do
        wrapper = Datadog::DI::SnapshotEncoder::ArrayNode.new
        wrapper.add_element(root)
        root = wrapper
      end

      expect(Thread.new { emitter.emit(root) }.value).to eq "#{"[" * 10_001}#{"]" * 10_001}"
    end
  end
end
