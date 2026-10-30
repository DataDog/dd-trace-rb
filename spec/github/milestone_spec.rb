# frozen_string_literal: true

require "spec_helper"
require_relative "../../.github/scripts/ci/milestone"

RSpec.describe CI::Milestone do
  subject(:update) { described_class.update(api, "owner/project", 9) }

  let(:api) { instance_double(CI::GitHub) }
  let(:path) { "repos/owner/project" }
  let(:pr) { {"merged" => true, "milestone" => nil, "merge_commit_sha" => "a" * 40, "base" => {"repo" => {"full_name" => "owner/project"}}} }
  let(:source) { "raise 'Version files must not be evaluated'\nMAJOR = 2\n" }
  let(:milestones) { [{"title" => "20.1.0", "number" => 20}, {"title" => "2.47.0", "number" => 2}] }

  before do
    allow(api).to receive(:get).with("#{path}/pulls/9").and_return(pr)
    allow(api).to receive(:get).with("#{path}/contents/lib/datadog/version.rb?ref=#{"a" * 40}")
      .and_return({"type" => "file", "encoding" => "base64", "content" => Base64.strict_encode64(source)})
    allow(api).to receive(:list).with("#{path}/milestones?state=open").and_return(milestones)
  end

  it "reads the literal version without evaluating code and matches a complete major component" do
    expect(api).to receive(:request).with("PATCH", "#{path}/issues/9", {milestone: 2})
    update
  end

  context "when the pull request was closed without merging" do
    before { pr["merged"] = false }

    it "does not assign a milestone" do
      expect(api).not_to receive(:request)
      update
    end
  end

  context "when a milestone has already been assigned" do
    before { pr["milestone"] = {"number" => 3} }

    it "preserves the assignment" do
      expect(api).not_to receive(:request)
      update
    end
  end

  context "when reading the version would require executing Ruby" do
    let(:source) { "MAJOR = Integer('2')\n" }

    it "rejects the version instead of evaluating it" do
      expect(api).not_to receive(:request)
      expect { update }.to raise_error("Could not find a literal major version")
    end
  end
end
