# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../../tasks/release_prep/release_notes"

RSpec.describe ReleasePrep::ReleaseNotes do
  around do |example|
    Dir.mktmpdir do |dir|
      @unreleased_dir = dir
      example.run
    end
  end

  def write_fragment(name, message)
    File.write(File.join(@unreleased_dir, name), {
      "type" => "Fixed",
      "prefix" => "Tracing",
      "pull_request" => "https://github.com/DataDog/dd-trace-rb/pull/1",
      "message" => message,
    }.to_json)
  end

  subject(:release_notes) do
    described_class.new(
      version: "2.43.0",
      fragments: ReleasePrep::Fragments.read_all(dir: @unreleased_dir),
      highlights: File.exist?(File.join(@unreleased_dir, "highlights.md")) ? File.read(File.join(@unreleased_dir, "highlights.md")) : nil,
    )
  end

  describe "#tag_name" do
    it "prefixes the version with v" do
      expect(release_notes.tag_name).to eq("v2.43.0")
    end
  end

  describe "#empty?" do
    it "is false when there are fragments" do
      write_fragment("1.json", "Fix a bug.")

      expect(release_notes.empty?).to be(false)
    end

    it "is false when there are only highlights" do
      File.write(File.join(@unreleased_dir, "highlights.md"), "## Highlights\n\nBig release!")

      expect(release_notes.empty?).to be(false)
    end

    it "is true when there are no fragments and no highlights" do
      expect(release_notes.empty?).to be(true)
    end
  end

  describe "#body" do
    it "renders the fragments as plain Markdown" do
      write_fragment("1.json", "Fix a bug.")

      expect(release_notes.body).to include("* Tracing: Fix a bug. (#1)")
    end

    it "prepends highlights when present" do
      write_fragment("1.json", "Fix a bug.")
      File.write(File.join(@unreleased_dir, "highlights.md"), "## Highlights\n\nBig release!")

      expect(release_notes.body).to start_with("## Highlights\n\nBig release!\n\n### Fixed")
    end
  end

  describe "#write" do
    it "writes the body to the output file and returns its path" do
      write_fragment("1.json", "Fix a bug.")
      output = File.join(@unreleased_dir, "release_body.md")

      result = release_notes.write(path: output)

      expect(result).to eq(output)
      expect(File.read(output)).to include("### Fixed")
    end

    it "creates the output directory when it does not exist" do
      write_fragment("1.json", "Fix a bug.")
      output = File.join(@unreleased_dir, "nested", "release_body.md")

      release_notes.write(path: output)

      expect(File.exist?(output)).to be(true)
    end

    it "fails loudly when there is nothing to release" do
      output = File.join(@unreleased_dir, "release_body.md")

      expect { release_notes.write(path: output) }.to raise_error(SystemExit)
    end
  end

  describe "#linkify!" do
    it "linkifies #NNNN references in the written file" do
      write_fragment("1.json", "Fix a bug.")
      output = release_notes.write(path: File.join(@unreleased_dir, "release_body.md"))

      release_notes.linkify!(path: output)

      expect(File.read(output)).to include("([#1][])")
      expect(File.read(output)).to include("[#1]: https://github.com/DataDog/dd-trace-rb/issues/1")
    end
  end
end
