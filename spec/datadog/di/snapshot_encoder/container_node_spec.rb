require "datadog/di/spec_helper"
require_relative "../snapshot_encoder_helpers"

RSpec.describe Datadog::DI::SnapshotEncoder::ContainerNode do
  include SnapshotEncoderHelpers

  def fragment(text)
    Datadog::DI::SnapshotEncoder::FragmentNode.new(text)
  end

  # Builds [[0, ..., 24] x 25] as nested ArrayNodes.
  let(:outer) do
    Datadog::DI::SnapshotEncoder::ArrayNode.new.tap do |outer|
      25.times do
        inner = Datadog::DI::SnapshotEncoder::ArrayNode.new
        25.times { |i| inner.add_element(fragment(i.to_s)) }
        outer.add_element(inner)
      end
    end
  end

  describe "#apply_child_delta" do
    it "keeps the sizes and prefix sizes of every ancestor exact" do
      outer.children[2].replace_child(4, fragment("\"#{"x" * 50}\""))
      outer.children[21].replace_child(23, fragment("\"#{"y" * 50}\""))

      expect_exact_sizes(outer)
    end

    it "adds the delta to the prefix size only through the first 20 children" do
      expect { outer.children[21].apply_child_delta(0, 5) }
        .to change(outer, :size).by(5).and change(outer, :prefix_size).by(0)
      expect { outer.children[1].apply_child_delta(22, 5) }
        .to change(outer, :size).by(5).and change(outer, :prefix_size).by(5)
    end
  end

  describe "#replace_child" do
    it "attaches the replacement at the replaced position" do
      replacement = fragment("null")
      outer.replace_child(7, replacement)

      expect(outer.children[7]).to equal replacement
      expect(replacement.parent).to equal outer
      expect(replacement.parent_index).to eq 7
    end

    it "raises IndexError for a position without a child" do
      expect { outer.replace_child(25, fragment("null")) }.to raise_error(IndexError)
    end
  end
end
