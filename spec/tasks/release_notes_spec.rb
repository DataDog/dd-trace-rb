# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../tasks/release_notes"

RSpec.describe ReleaseNotes, webmock: true do
  describe ".create_draft_release" do
    let(:version) { "2.36.0" }
    let(:releases_url) { "https://api.github.com/repos/DataDog/dd-trace-rb/releases" }

    around do |example|
      original = ENV["GITHUB_TOKEN"]
      ENV["GITHUB_TOKEN"] = "test-token"
      example.run
      ENV["GITHUB_TOKEN"] = original
    end

    it "creates a draft release with the given tag and body" do
      stub = stub_request(:post, releases_url)
        .with(
          body: hash_including("tag_name" => "v2.36.0", "draft" => true, "body" => "* Fix a bug."),
        )
        .to_return(status: 201, body: "{}")

      described_class.create_draft_release(version, "* Fix a bug.")

      expect(stub).to have_been_requested
    end

    it "fails loudly on a non-2xx response" do
      stub_request(:post, releases_url).to_return(status: 422, body: "unprocessable")

      expect { described_class.create_draft_release(version, "* Fix a bug.") }
        .to raise_error(SystemExit)
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

  describe ".validate_examples!" do
    it "passes when every example is schema-valid" do
      FileUtils.mkdir_p(File.join(@unreleased_dir, "examples"))
      write_fragment("examples/basic.json", {
        "type" => "Added",
        "prefix" => "Core",
        "pull_request" => "https://github.com/DataDog/dd-trace-rb/pull/1",
        "message" => "Example entry.",
      })

      expect { described_class.validate_examples!(dir: @unreleased_dir) }.not_to raise_error
    end

    it "raises when an example is schema-invalid" do
      FileUtils.mkdir_p(File.join(@unreleased_dir, "examples"))
      write_fragment("examples/broken.json", {
        "type" => "NotARealType",
        "prefix" => "Core",
        "pull_request" => "https://github.com/DataDog/dd-trace-rb/pull/1",
        "message" => "Broken example.",
      })

      expect { described_class.validate_examples!(dir: @unreleased_dir) }
        .to raise_error(ReleaseNotes::Fragments::ValidationError, /broken\.json/)
    end

    it "passes when there is no examples directory" do
      expect { described_class.validate_examples!(dir: @unreleased_dir) }.not_to raise_error
    end
  end

  describe ".render" do
    def entry(type:, prefix:, pr:, message:, author: nil)
      e = {
        "type" => type,
        "prefix" => prefix,
        "pull_request" => "https://github.com/DataDog/dd-trace-rb/pull/#{pr}",
        "message" => message,
      }
      e["author"] = author if author
      e
    end

    it "groups entries by type into headed sections" do
      entries = [
        entry(type: "Fixed", prefix: "Tracing", pr: 100, message: "Fix a bug."),
        entry(type: "Added", prefix: "Core", pr: 101, message: "Add a thing."),
      ]

      result = described_class.render(entries)

      expect(result).to include("### Added")
      expect(result).to include("### Fixed")
      expect(result.index("### Added")).to be < result.index("### Fixed")
    end

    it "omits sections with no entries" do
      entries = [entry(type: "Fixed", prefix: "Tracing", pr: 100, message: "Fix a bug.")]

      result = described_class.render(entries)

      expect(result).not_to include("### Added")
      expect(result).not_to include("### Changed")
    end

    it "sorts entries within a section by prefix" do
      entries = [
        entry(type: "Fixed", prefix: "Tracing", pr: 100, message: "Tracing fix."),
        entry(type: "Fixed", prefix: "AppSec", pr: 101, message: "AppSec fix."),
      ]

      result = described_class.render(entries)

      expect(result.index("AppSec fix.")).to be < result.index("Tracing fix.")
    end

    it "renders the prefix, message, and linked PR number" do
      entries = [entry(type: "Fixed", prefix: "Tracing", pr: 6300, message: "Fix a bug.")]

      result = described_class.render(entries)

      expect(result).to include("* Tracing: Fix a bug. ([#6300][])")
      expect(result).to include("[#6300]: https://github.com/DataDog/dd-trace-rb/issues/6300")
    end

    it "renders the author credit and link when present" do
      entries = [entry(type: "Fixed", prefix: "Tracing", pr: 6300, message: "Fix a bug.", author: "octocat")]

      result = described_class.render(entries)

      expect(result).to include("([@octocat][])")
      expect(result).to include("[@octocat]: https://github.com/octocat")
    end

    it "preserves Markdown formatting in the message" do
      entries = [entry(type: "Fixed", prefix: "Tracing", pr: 100, message: "Fix `ActiveRecord` bug.")]

      result = described_class.render(entries)

      expect(result).to include("Fix `ActiveRecord` bug.")
    end

    it "prepends highlights, blank-line separated, when given" do
      entries = [entry(type: "Fixed", prefix: "Tracing", pr: 100, message: "Fix a bug.")]

      result = described_class.render(entries, highlights: "## Highlights\n\nBig release!")

      expect(result).to start_with("## Highlights\n\nBig release!\n\n### Fixed")
    end

    it "returns an empty string when there are no entries and no highlights" do
      expect(described_class.render([])).to eq("")
    end
  end

  describe ".consume!" do
    it "deletes exactly the files backing the given entries" do
      write_fragment("keep.json", {
        "type" => "Fixed", "prefix" => "Tracing",
        "pull_request" => "https://github.com/DataDog/dd-trace-rb/pull/1", "message" => "Keep me.",
      })
      write_fragment("consume.json", {
        "type" => "Fixed", "prefix" => "Tracing",
        "pull_request" => "https://github.com/DataDog/dd-trace-rb/pull/2", "message" => "Consume me.",
      })
      entries = described_class.read_all(dir: @unreleased_dir).select { |e| e["message"] == "Consume me." }

      described_class.consume!(entries)

      expect(File.exist?(File.join(@unreleased_dir, "consume.json"))).to be false
      expect(File.exist?(File.join(@unreleased_dir, "keep.json"))).to be true
    end

    it "deletes the highlights file when given and present" do
      highlights_path = File.join(@unreleased_dir, "highlights.md")
      File.write(highlights_path, "# Highlights")

      described_class.consume!([], highlights_path: highlights_path)

      expect(File.exist?(highlights_path)).to be false
    end

    it "does not raise when highlights_path is given but absent" do
      missing_path = File.join(@unreleased_dir, "highlights.md")

      expect { described_class.consume!([], highlights_path: missing_path) }.not_to raise_error
    end
  end
end
