# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../tasks/release_body"

RSpec.describe ReleaseNotes::ReleaseBody do
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

  describe ".write" do
    it "writes the rendered fragments to the output file and returns its path" do
      write_fragment("1.json", "Fix a bug.")
      output = File.join(@unreleased_dir, "release_body.md")

      result = described_class.write(dir: @unreleased_dir, path: output)

      expect(result).to eq(output)
      expect(File.read(output)).to include("### Fixed")
      expect(File.read(output)).to include("* Tracing: Fix a bug. (#1)")
    end

    it "prepends highlights when present" do
      write_fragment("1.json", "Fix a bug.")
      File.write(File.join(@unreleased_dir, "highlights.md"), "## Highlights\n\nBig release!")
      output = File.join(@unreleased_dir, "release_body.md")

      described_class.write(dir: @unreleased_dir, path: output)

      body = File.read(output)
      expect(body).to start_with("## Highlights\n\nBig release!\n\n### Fixed")
    end

    it "creates the output directory when it does not exist" do
      write_fragment("1.json", "Fix a bug.")
      output = File.join(@unreleased_dir, "nested", "release_body.md")

      described_class.write(dir: @unreleased_dir, path: output)

      expect(File.exist?(output)).to be true
    end

    it "fails loudly when there are no fragments and no highlights" do
      output = File.join(@unreleased_dir, "release_body.md")

      expect { described_class.write(dir: @unreleased_dir, path: output) }
        .to raise_error(SystemExit)
    end

    it "allows a highlights-only release" do
      File.write(File.join(@unreleased_dir, "highlights.md"), "## Highlights\n\nBig release!")
      output = File.join(@unreleased_dir, "release_body.md")

      expect { described_class.write(dir: @unreleased_dir, path: output) }.not_to raise_error

      expect(File.read(output)).to eq("## Highlights\n\nBig release!")
    end
  end
end
