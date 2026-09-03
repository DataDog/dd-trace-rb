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

  describe ".fail_if_nothing_to_release!" do
    let(:fragments) { ReleasePrep::Fragments.new([]) }
    let(:highlights) { ReleasePrep::Highlights::Missing.new }

    it "fails when there are no fragments and no highlights" do
      expect { described_class.fail_if_nothing_to_release!(fragments, highlights) }
        .to raise_error(SystemExit)
    end

    it "passes when there are fragments" do
      expect { described_class.fail_if_nothing_to_release!(ReleasePrep::Fragments.new([:fragment]), highlights) }
        .not_to raise_error
    end

    it "passes when there are only highlights" do
      highlights = ReleasePrep::Highlights.new(File.join(Dir.mktmpdir, "highlights.md"))
      allow(highlights).to receive(:empty?).and_return(false)

      expect { described_class.fail_if_nothing_to_release!(fragments, highlights) }.not_to raise_error
    end
  end
end
