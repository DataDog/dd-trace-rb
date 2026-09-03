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
end
