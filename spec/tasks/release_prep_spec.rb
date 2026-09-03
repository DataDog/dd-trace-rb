# frozen_string_literal: true

require "spec_helper"
require "stringio"
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
end
