# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../../../tasks/release_prep/fragment_template"

RSpec.describe ReleasePrep::FragmentTemplate do
  describe ".write" do
    it "writes a timestamp-named fragment into the given directory" do
      Dir.mktmpdir do |dir|
        path = described_class.write(dir: dir)

        expect(path).to start_with("#{dir}/")
        expect(File.basename(path)).to match(/\A\d{14}\.json\z/)
        expect(JSON.parse(File.read(path))).to eq(described_class.content)
      end
    end

    it "carries every required field" do
      expect(described_class.content.keys).to include(*ReleasePrep::Fragment::REQUIRED_FIELDS)
    end

    it "lists the valid types and products, so the guidance cannot go stale" do
      expect(described_class.content["type"]).to eq(ReleasePrep::Fragment::TYPES.join(" | "))
      expect(described_class.content["product"]).to eq(ReleasePrep::Fragment::PRODUCTS.join(" | "))
    end
  end

  describe "a fresh scaffold" do
    it "fails lint, so a committed placeholder cannot pass CI" do
      Dir.mktmpdir do |dir|
        fragment = ReleasePrep::Fragment.read(described_class.write(dir: dir))

        expect(fragment.errors).not_to be_empty
      end
    end

    it "passes lint once filled in as the placeholders instruct" do
      Dir.mktmpdir do |dir|
        path = described_class.write(dir: dir)
        entry = JSON.parse(File.read(path))
        entry["type"] = entry["type"].split(" | ").first
        entry["product"] = entry["product"].split(" | ").first
        entry["pull_request"] = entry["pull_request"].sub("NNNN", "1234")
        entry["message"] = "Fix a bug."
        File.write(path, JSON.pretty_generate(entry))

        expect(ReleasePrep::Fragment.read(path).errors).to be_empty
      end
    end
  end
end
