# frozen_string_literal: true

require "spec_helper"
require "rake"

Rake.application ||= Rake::Application.new
load File.expand_path("../../tasks/release_prep.rake", __dir__) unless defined?(ReleasePrep)

RSpec.describe ReleasePrep, webmock: true do
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
