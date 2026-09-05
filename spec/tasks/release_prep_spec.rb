# frozen_string_literal: true

require "spec_helper"
require "stringio"
require "tmpdir"
require "fileutils"
require_relative "../../tasks/release_prep"

RSpec.describe ReleasePrep do
  describe ".fail!" do
    it "exits with a GitHub Actions error annotation on stderr" do
      stderr = StringIO.new
      original_stderr, $stderr = $stderr, stderr

      expect { described_class.fail!("boom") }.to raise_error(SystemExit)

      $stderr = original_stderr
      expect(stderr.string).to eq("::error::boom\n")
    end
  end

  describe ".fail_all!" do
    it "exits after emitting one error annotation per violation" do
      stderr = StringIO.new
      original_stderr, $stderr = $stderr, stderr

      expect { described_class.fail_all!(["first", "second"]) }.to raise_error(SystemExit)

      $stderr = original_stderr
      expect(stderr.string).to eq("::error::first\n::error::second\n")
    end
  end

  describe ".validate_fragments!" do
    def fragment(entry)
      ReleasePrep::Fragment.new("unreleased/1.json", entry)
    end

    def valid_entry(overrides = {})
      {
        "type" => "Fixed",
        "prefix" => "Tracing",
        "pull_request" => "https://github.com/DataDog/dd-trace-rb/pull/1",
        "message" => "Fix a bug.",
      }.merge(overrides)
    end

    it "passes silently when every fragment is valid" do
      fragments = ReleasePrep::Fragments.new([fragment(valid_entry)])

      expect { described_class.validate_fragments!(fragments) }.not_to raise_error
    end

    it "emits every violation and exits when a fragment is invalid" do
      stderr = StringIO.new
      original_stderr, $stderr = $stderr, stderr
      fragments = ReleasePrep::Fragments.new([
        fragment(valid_entry("type" => "Removed")),
        fragment(valid_entry("prefix" => "Redis")),
      ])

      expect { described_class.validate_fragments!(fragments) }.to raise_error(SystemExit)

      $stderr = original_stderr
      expect(stderr.string).to include("::error::unreleased/1.json: type")
      expect(stderr.string).to include("::error::unreleased/1.json: prefix")
    end
  end

  describe "ValidationError" do
    it "is a StandardError" do
      expect(described_class::ValidationError < StandardError).to be(true)
    end
  end

  describe ".fail_if_no_fragments!" do
    it "fails when there are no changelog fragments" do
      expect { described_class.fail_if_no_fragments!(ReleasePrep::Fragments.new([])) }
        .to raise_error(SystemExit)
    end

    it "passes when there are fragments" do
      expect { described_class.fail_if_no_fragments!(ReleasePrep::Fragments.new([:fragment])) }
        .not_to raise_error
    end
  end

  describe ".merged_pr_numbers" do
    it "collects PR numbers from squash-merge and merge-commit subjects" do
      subjects = [
        "Fix a rare crash in the profiler (#6142)",
        "Merge pull request #6100 from DataDog/fix",
        "A direct commit with no PR",
      ]

      expect(described_class.merged_pr_numbers(commit_subjects: subjects)).to contain_exactly("6142", "6100")
    end
  end

  describe ".validate_pr_numbers!" do
    def fragment(pr_number)
      ReleasePrep::Fragment.new(
        "unreleased/#{pr_number}.json",
        {
          "type" => "Fixed",
          "prefix" => "Tracing",
          "pull_request" => "https://github.com/DataDog/dd-trace-rb/pull/#{pr_number}",
          "message" => "Fix a bug.",
        },
      )
    end

    it "passes when every fragment's PR number is in the merged set" do
      fragments = ReleasePrep::Fragments.new([fragment("6142"), fragment("6100")])

      expect { described_class.validate_pr_numbers!(fragments, pr_numbers: %w[6142 6100]) }
        .not_to raise_error
    end

    it "reports every unresolved PR in one pass, naming file and number" do
      stderr = StringIO.new
      original_stderr, $stderr = $stderr, stderr
      fragments = ReleasePrep::Fragments.new([fragment("6142"), fragment("999999"), fragment("888888")])

      begin
        expect { described_class.validate_pr_numbers!(fragments, pr_numbers: %w[6142 6100]) }
          .to raise_error(SystemExit)
      ensure
        $stderr = original_stderr
      end

      expect(stderr.string).to eq(
        "::error::unreleased/999999.json: pull_request does not match any merged PR in this repository " \
        "(#999999)\n" \
        "::error::unreleased/888888.json: pull_request does not match any merged PR in this repository " \
        "(#888888)\n",
      )
    end
  end
end
