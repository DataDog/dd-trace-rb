# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../../../tasks/release_prep/changelog"

RSpec.describe ReleasePrep::Changelog do
  let(:changelog_fixture) do
    <<~MD
      # CHANGELOG

      ## [Unreleased]

      ## [2.42.0] - 2026-08-31

      ### Added

      * Tracing: Add a thing. ([#6300][])

      [Unreleased]: https://github.com/DataDog/dd-trace-rb/compare/v2.42.0...master
      [2.42.0]: https://github.com/DataDog/dd-trace-rb/compare/v2.41.0...v2.42.0
    MD
  end

  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      example.run
    end
  end

  def write_changelog(content = nil)
    content ||= changelog_fixture

    path = File.join(@dir, "CHANGELOG.md")
    File.write(path, content)
    path
  end

  subject(:changelog) { described_class.new(path: write_changelog) }

  describe "#previous_version" do
    it "extracts the previous version from the [Unreleased] compare link" do
      expect(changelog.previous_version).to eq("2.42.0")
    end

    it "fails loudly when the compare link is missing" do
      changelog = described_class.new(path: write_changelog("## [Unreleased]\n"))

      expect { changelog.previous_version }.to raise_error(SystemExit)
    end
  end

  describe "#insert_version" do
    it "inserts the new section directly under [Unreleased]" do
      changelog.insert_version("2.43.0", "### Fixed\n\n* Tracing: Fix a bug. (#1)")

      content = File.read(File.join(@dir, "CHANGELOG.md"))
      expect(content).to match(/\A# CHANGELOG\n\n## \[Unreleased\]\n\n## \[2\.43\.0\] - \d{4}-\d{2}-\d{2}\n\n### Fixed/)
      expect(content).to include("## [2.42.0]")
    end

    it "fails loudly when the [Unreleased] marker is missing" do
      changelog = described_class.new(path: write_changelog("# CHANGELOG\n"))

      expect { changelog.insert_version("2.43.0", "") }.to raise_error(SystemExit)
    end

    it "fails loudly rather than splicing into the footer when only the compare link matches" do
      footer_only = <<~MD
        # CHANGELOG

        ## [2.42.0] - 2026-08-31

        [Unreleased]: https://github.com/DataDog/dd-trace-rb/compare/v2.42.0...master
      MD
      changelog = described_class.new(path: write_changelog(footer_only))

      expect { changelog.insert_version("2.43.0", "### Fixed\n\n* Tracing: Fix a bug. (#1)") }
        .to raise_error(SystemExit)
    end
  end

  describe "#rewrite_footer" do
    it "points [Unreleased] at the new version and adds the new compare link" do
      changelog.insert_version("2.43.0", "### Fixed\n\n* Tracing: Fix a bug. (#1)")
      changelog.rewrite_footer("2.43.0", "2.42.0")

      content = File.read(File.join(@dir, "CHANGELOG.md"))
      expect(content).to include("[Unreleased]: https://github.com/DataDog/dd-trace-rb/compare/v2.43.0...master")
      expect(content).to include("[2.43.0]: https://github.com/DataDog/dd-trace-rb/compare/v2.42.0...v2.43.0")
      expect(content).not_to include("[Unreleased]: https://github.com/DataDog/dd-trace-rb/compare/v2.42.0...master")
    end

    it "fails loudly when the [Unreleased] compare link is missing" do
      changelog = described_class.new(path: write_changelog("## [Unreleased]\n"))

      expect { changelog.rewrite_footer("2.43.0", "2.42.0") }.to raise_error(SystemExit)
    end
  end
end
