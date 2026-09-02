# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../tasks/release_notes"

RSpec.describe ReleaseNotes, webmock: true do
  describe ".draft_changelog" do
    let(:version) { "2.36.0" }
    let(:releases_url) { "https://api.github.com/repos/DataDog/dd-trace-rb/releases?per_page=100" }

    def stub_releases(body:)
      stub_request(:get, releases_url).to_return(
        status: 200,
        body: [
          {"tag_name" => "v2.36.0", "draft" => true, "body" => body},
        ].to_json,
      )
    end

    it "normalizes CRLF line endings from the GitHub API response to LF" do
      stub_releases(body: "* Fix a bug\r\n* Fix another bug\r\n")

      expect(described_class.draft_changelog(version)).to eq("* Fix a bug\n* Fix another bug")
    end

    it "normalizes lone CR line endings to LF" do
      stub_releases(body: "* Fix a bug\r* Fix another bug\r")

      expect(described_class.draft_changelog(version)).to eq("* Fix a bug\n* Fix another bug")
    end

    it "leaves LF-only bodies unchanged" do
      stub_releases(body: "* Fix a bug\n* Fix another bug\n")

      expect(described_class.draft_changelog(version)).to eq("* Fix a bug\n* Fix another bug")
    end

    it "keeps only the content after the changelog marker" do
      stub_releases(body: "Highlights\r\n<!-- changelog -->\r\n* Fix a bug\r\n")

      expect(described_class.draft_changelog(version)).to eq("* Fix a bug")
    end
  end
end

RSpec.describe ReleaseNotes::Fragments do
  around do |example|
    Dir.mktmpdir do |dir|
      @unreleased_dir = dir
      example.run
    end
  end

  def write_fragment(name, content)
    File.write(File.join(@unreleased_dir, name), content.to_json)
  end

  describe ".read_all" do
    it "reads a valid fragment" do
      write_fragment("1.json", {
        "type" => "Fixed",
        "prefix" => "Tracing",
        "pull_request" => "https://github.com/DataDog/dd-trace-rb/pull/6300",
        "message" => "Fix a bug.",
      })

      entries = described_class.read_all(dir: @unreleased_dir)

      expect(entries.size).to eq(1)
      expect(entries.first["type"]).to eq("Fixed")
      expect(entries.first["message"]).to eq("Fix a bug.")
    end

    it "includes the optional author field when present" do
      write_fragment("1.json", {
        "type" => "Added",
        "prefix" => "Core",
        "pull_request" => "https://github.com/DataDog/dd-trace-rb/pull/1",
        "message" => "Add a thing.",
        "author" => "octocat",
      })

      entries = described_class.read_all(dir: @unreleased_dir)

      expect(entries.first["author"]).to eq("octocat")
    end

    it "skips files under an examples/ subdirectory" do
      FileUtils.mkdir_p(File.join(@unreleased_dir, "examples"))
      write_fragment("examples/basic.json", {
        "type" => "Added",
        "prefix" => "Core",
        "pull_request" => "https://github.com/DataDog/dd-trace-rb/pull/1",
        "message" => "Example entry.",
      })

      entries = described_class.read_all(dir: @unreleased_dir)

      expect(entries).to be_empty
    end

    it "skips highlights.md" do
      File.write(File.join(@unreleased_dir, "highlights.md"), "# Highlights")

      entries = described_class.read_all(dir: @unreleased_dir)

      expect(entries).to be_empty
    end

    it "skips non-.json files" do
      File.write(File.join(@unreleased_dir, "README.md"), "docs")

      entries = described_class.read_all(dir: @unreleased_dir)

      expect(entries).to be_empty
    end

    it "raises on invalid JSON, naming the file" do
      File.write(File.join(@unreleased_dir, "bad.json"), "{not json")

      expect { described_class.read_all(dir: @unreleased_dir) }
        .to raise_error(ReleaseNotes::Fragments::ValidationError, /bad\.json/)
    end

    it "raises when a required field is missing" do
      write_fragment("1.json", {
        "type" => "Fixed",
        "prefix" => "Tracing",
        "message" => "Missing pull_request.",
      })

      expect { described_class.read_all(dir: @unreleased_dir) }
        .to raise_error(ReleaseNotes::Fragments::ValidationError, /pull_request/)
    end

    it "raises when type is not in the closed enum" do
      write_fragment("1.json", {
        "type" => "Removed",
        "prefix" => "Tracing",
        "pull_request" => "https://github.com/DataDog/dd-trace-rb/pull/1",
        "message" => "Bad type.",
      })

      expect { described_class.read_all(dir: @unreleased_dir) }
        .to raise_error(ReleaseNotes::Fragments::ValidationError, /type/)
    end

    it "raises when prefix is not in the closed enum" do
      write_fragment("1.json", {
        "type" => "Fixed",
        "prefix" => "Redis",
        "pull_request" => "https://github.com/DataDog/dd-trace-rb/pull/1",
        "message" => "Bad prefix.",
      })

      expect { described_class.read_all(dir: @unreleased_dir) }
        .to raise_error(ReleaseNotes::Fragments::ValidationError, /prefix/)
    end
  end
end
