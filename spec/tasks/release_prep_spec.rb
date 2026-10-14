# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../tasks/lib/release_prep"

RSpec.describe ReleasePrep do
  describe ".fail!" do
    it "exits with a GitHub Actions error annotation on stderr" do
      stderr = capture_stderr { expect { described_class.fail!("boom") }.to raise_error(SystemExit) }

      expect(stderr).to eq("::error::boom\n")
    end
  end

  describe ".fail_all!" do
    it "exits after emitting one error annotation per violation" do
      stderr = capture_stderr { expect { described_class.fail_all!(["first", "second"]) }.to raise_error(SystemExit) }

      expect(stderr).to eq("::error::first\n::error::second\n")
    end
  end

  describe ".validate_fragments!" do
    def fragment(entry)
      ReleasePrep::Fragment.new("unreleased/1.json", entry)
    end

    def valid_entry(overrides = {})
      {
        "type" => "Fixed",
        "product" => "Tracing",
        "pull_request" => "https://github.com/DataDog/dd-trace-rb/pull/1",
        "message" => "Fix a bug.",
      }.merge(overrides)
    end

    it "passes silently when every fragment is valid" do
      fragments = ReleasePrep::Fragments.new([fragment(valid_entry)])

      expect { described_class.validate_fragments!(fragments) }.not_to raise_error
    end

    it "emits every violation and exits when a fragment is invalid" do
      fragments = ReleasePrep::Fragments.new([
        fragment(valid_entry("type" => "Removed")),
        fragment(valid_entry("product" => "Redis")),
      ])

      stderr = capture_stderr { expect { described_class.validate_fragments!(fragments) }.to raise_error(SystemExit) }

      expect(stderr).to include("::error::unreleased/1.json: type")
      expect(stderr).to include("::error::unreleased/1.json: product")
    end
  end

  describe "ValidationError" do
    it "is a StandardError" do
      expect(described_class::ValidationError < StandardError).to be(true)
    end
  end

  describe ".fail_if_no_fragments!" do
    it "fails when there are no changelog fragments" do
      stderr = capture_stderr do
        expect { described_class.fail_if_no_fragments!(ReleasePrep::Fragments.new([])) }.to raise_error(SystemExit)
      end

      expect(stderr).to include("::error::No changelog fragments found in unreleased/")
    end

    it "passes when there are fragments" do
      expect { described_class.fail_if_no_fragments!(ReleasePrep::Fragments.new([:fragment])) }
        .not_to raise_error
    end
  end
end
