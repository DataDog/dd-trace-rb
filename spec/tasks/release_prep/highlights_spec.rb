# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../../tasks/release_prep/highlights"

RSpec.describe ReleasePrep::Highlights do
  around do |example|
    Dir.mktmpdir do |dir|
      @unreleased_dir = dir
      example.run
    end
  end

  def highlights_path
    File.join(@unreleased_dir, "highlights.md")
  end

  describe ".read" do
    it "reads the highlights file from the directory" do
      File.write(highlights_path, "## Highlights\n\nBig release!")

      highlights = described_class.read(dir: @unreleased_dir)

      expect(highlights.to_s).to eq("## Highlights\n\nBig release!")
      expect(highlights.empty?).to be(false)
    end

    it "returns the null object when the file is missing" do
      highlights = described_class.read(dir: @unreleased_dir)

      expect(highlights).to be_instance_of(described_class::Missing)
      expect(highlights.to_s).to eq("")
      expect(highlights.empty?).to be(true)
    end

    it "is still the real object when the file is present but blank" do
      File.write(highlights_path, "  \n")

      highlights = described_class.read(dir: @unreleased_dir)

      expect(highlights).to be_instance_of(described_class)
      expect(highlights.empty?).to be(true)
    end
  end

  describe "#delete!" do
    it "deletes the highlights file when present" do
      File.write(highlights_path, "# Highlights")

      described_class.read(dir: @unreleased_dir).delete!

      expect(File.exist?(highlights_path)).to be(false)
    end

    it "is a no-op on the null object" do
      expect { described_class.read(dir: @unreleased_dir).delete! }.not_to raise_error
    end
  end

  describe ReleasePrep::Highlights::Missing do
    it "shares the Highlights API with inert behavior" do
      expect(described_class.new.to_s).to eq("")
      expect(described_class.new.empty?).to be(true)
      expect { described_class.new.delete! }.not_to raise_error
    end
  end
end
