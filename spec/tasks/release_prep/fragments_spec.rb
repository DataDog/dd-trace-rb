# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../../tasks/release_prep/fragments"

RSpec.describe ReleasePrep::Fragments do
  around do |example|
    Dir.mktmpdir do |dir|
      @unreleased_dir = dir
      example.run
    end
  end

  def write_fragment(name, entry)
    File.write(File.join(@unreleased_dir, name), entry.to_json)
  end

  def valid_entry(overrides = {})
    {
      "type" => "Fixed",
      "prefix" => "Tracing",
      "pull_request" => "https://github.com/DataDog/dd-trace-rb/pull/1",
      "message" => "Fix a bug.",
    }.merge(overrides)
  end

  describe ".read_all" do
    it "collects every fragment in the directory" do
      write_fragment("1.json", valid_entry)
      write_fragment("2.json", valid_entry("message" => "Fix another bug."))

      fragments = described_class.read_all(dir: @unreleased_dir)

      expect(fragments.map(&:message)).to contain_exactly("Fix a bug.", "Fix another bug.")
    end

    it "skips files under an examples/ subdirectory, highlights.md, and non-JSON files" do
      FileUtils.mkdir_p(File.join(@unreleased_dir, "examples"))
      write_fragment("examples/basic.json", valid_entry)
      File.write(File.join(@unreleased_dir, "highlights.md"), "# Highlights")
      File.write(File.join(@unreleased_dir, "README.md"), "docs")

      expect(described_class.read_all(dir: @unreleased_dir)).to be_empty
    end

    it "raises on the first invalid fragment" do
      write_fragment("1.json", valid_entry("type" => "Removed"))

      expect { described_class.read_all(dir: @unreleased_dir) }
        .to raise_error(ReleasePrep::ValidationError, /1\.json/)
    end
  end

  describe ".read_examples" do
    it "collects example fragments without counting them as pending entries" do
      FileUtils.mkdir_p(File.join(@unreleased_dir, "examples"))
      write_fragment("examples/basic.json", valid_entry)

      examples = described_class.read_examples(dir: @unreleased_dir)

      expect(examples.size).to eq(1)
      expect(described_class.read_all(dir: @unreleased_dir)).to be_empty
    end

    it "raises when an example is invalid, naming the file" do
      FileUtils.mkdir_p(File.join(@unreleased_dir, "examples"))
      write_fragment("examples/broken.json", valid_entry("type" => "NotARealType"))

      expect { described_class.read_examples(dir: @unreleased_dir) }
        .to raise_error(ReleasePrep::ValidationError, /broken\.json/)
    end

    it "is empty when there is no examples directory" do
      expect(described_class.read_examples(dir: @unreleased_dir)).to be_empty
    end
  end

  describe "#render" do
    def fragments_for(*entries)
      dir = @unreleased_dir
      entries.each_with_index do |entry, index|
        write_fragment("#{index}.json", entry)
      end
      described_class.read_all(dir: dir)
    end

    it "groups fragments by type into headed sections" do
      fragments = fragments_for(
        valid_entry("type" => "Fixed", "message" => "Fix a bug."),
        valid_entry("type" => "Added", "message" => "Add a thing."),
      )

      result = fragments.render

      expect(result).to include("### Added")
      expect(result).to include("### Fixed")
      expect(result.index("### Added")).to be < result.index("### Fixed")
    end

    it "omits sections with no fragments" do
      fragments = fragments_for(valid_entry)

      result = fragments.render

      expect(result).not_to include("### Added")
      expect(result).not_to include("### Changed")
    end

    it "sorts fragments within a section by the declared prefix order, not alphabetically" do
      fragments = fragments_for(
        valid_entry("prefix" => "Tracing", "message" => "Tracing fix."),
        valid_entry("prefix" => "AppSec", "message" => "AppSec fix."),
        valid_entry("prefix" => "Core", "message" => "Core fix."),
      )

      result = fragments.render

      expect(result.index("Core fix.")).to be < result.index("Tracing fix.")
      expect(result.index("Tracing fix.")).to be < result.index("AppSec fix.")
    end

    it "renders each fragment's line without linkification" do
      fragments = fragments_for(
        valid_entry(
          "pull_request" => "https://github.com/DataDog/dd-trace-rb/pull/6300",
          "message" => "Fix a bug.",
        ).merge("author" => "octocat"),
      )

      result = fragments.render

      expect(result).to include("* Tracing: Fix a bug. (#6300) (@octocat)")
      expect(result).not_to include("[]")
    end

    it "returns an empty string when there are no fragments" do
      expect(described_class.new([]).render).to eq("")
    end
  end

  describe "#consume!" do
    it "deletes exactly its own fragments' files" do
      write_fragment("keep.json", valid_entry("message" => "Keep me."))
      write_fragment("consume.json", valid_entry("message" => "Consume me."))
      consume_only = described_class.new(
        described_class.read_all(dir: @unreleased_dir).select { |f| f.message == "Consume me." }
      )

      consume_only.consume!

      expect(File.exist?(File.join(@unreleased_dir, "consume.json"))).to be(false)
      expect(File.exist?(File.join(@unreleased_dir, "keep.json"))).to be(true)
    end

    it "deletes every fragment's file" do
      write_fragment("1.json", valid_entry)
      write_fragment("2.json", valid_entry("message" => "Fix another bug."))

      described_class.read_all(dir: @unreleased_dir).consume!

      expect(Dir[File.join(@unreleased_dir, "*.json")]).to be_empty
    end
  end

  it "is Enumerable" do
    write_fragment("1.json", valid_entry)

    fragments = described_class.read_all(dir: @unreleased_dir)

    expect(fragments.map(&:message)).to eq(["Fix a bug."])
    expect(fragments.size).to eq(1)
    expect(fragments).not_to be_empty
    expect(described_class.new([])).to be_empty
  end
end
