# frozen_string_literal: true

require "spec_helper"
require_relative "../../.github/scripts/ci/required_checks"

RSpec.describe CI::RequiredChecks do
  subject(:failures) { described_class.failures(checks, files) }

  let(:files) { [] }
  let(:checks) do
    described_class::NAMES.each_with_index.map do |name, index|
      {"id" => index + 1, "name" => name, "app" => {"slug" => "github-actions"}, "status" => "completed", "conclusion" => "success"}
    end
  end

  it "accepts completed validation even when an optional report failed" do
    checks << {"id" => 100, "name" => "dd/junit", "app" => {"slug" => "github-actions"}, "status" => "completed", "conclusion" => "failure"}
    is_expected.to be_empty
  end

  it "rejects an absent required check" do
    missing = checks.pop.fetch("name")
    is_expected.to include("#{missing}: missing")
  end

  ["skipped", "neutral", "failure", "cancelled"].each do |conclusion|
    it "rejects a #{conclusion} required check" do
      checks.first["conclusion"] = conclusion
      is_expected.to include("Build Gem (complete): #{conclusion}")
    end
  end

  it "does not accept a check from another app with the required name" do
    checks.first["app"] = {"slug" => "another-app"}
    is_expected.to include("Build Gem (complete): missing")
  end

  it "uses the newest attempt rather than an older successful check" do
    checks << checks.first.merge("id" => 100, "status" => "in_progress", "conclusion" => nil)
    is_expected.to include("Build Gem (complete): in_progress")
  end

  context "when a hook was renamed out of its directory" do
    let(:files) { [{"filename" => "other/path", "previous_filename" => ".claude/hooks/guard.rb"}] }

    it "still requires hook validation" do
      is_expected.to include("Claude Hook Tests: missing")
    end
  end
end
