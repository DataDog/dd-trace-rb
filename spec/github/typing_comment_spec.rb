# frozen_string_literal: true

require "spec_helper"
require_relative "../../.github/scripts/ci/typing_comment"

RSpec.describe CI::TypingComment do
  subject(:publisher) { described_class.new(api, repository, event) }

  let(:api) { instance_double(CI::GitHub) }
  let(:repository) { "owner/project" }
  let(:path) { "repos/#{repository}" }
  let(:sha) { "a" * 40 }
  let(:event) { {"id" => 100, "head_sha" => sha, "run_attempt" => 1, "pull_requests" => []} }
  let(:run) do
    event.merge(
      "workflow_id" => 7,
      "path" => ".github/workflows/typing-stats.yml",
      "event" => "pull_request",
      "status" => "completed",
      "conclusion" => "success",
      "repository" => {"full_name" => repository},
      "head_repository" => {"id" => 20},
      "head_branch" => "contribution",
    )
  end
  let(:pr) do
    {
      "number" => 9,
      "state" => "open",
      "base" => {"repo" => {"full_name" => repository}},
      "head" => {"sha" => sha, "repo" => {"id" => 20}, "ref" => "contribution"},
    }
  end
  let(:pulls) { [pr] }
  let(:fresh_pr) { pr }
  let(:runs) { [run] }
  let(:artifacts) { [{"name" => "typing-stats-1-changed", "expired" => false}] }
  let(:comments) { [] }

  before do
    allow(api).to receive(:get).with("#{path}/actions/runs/100").and_return(run)
    allow(api).to receive(:get).with("#{path}/actions/workflows/typing-stats.yml").and_return({"id" => 7})
    allow(api).to receive(:get).with("#{path}/pulls/9").and_return(fresh_pr)
    allow(api).to receive(:list).with("#{path}/commits/#{sha}/pulls").and_return(pulls)
    allow(api).to receive(:list).with("#{path}/actions/workflows/typing-stats.yml/runs?event=pull_request&head_sha=#{sha}", key: "workflow_runs").and_return(runs)
    allow(api).to receive(:list).with("#{path}/actions/runs/100/artifacts", key: "artifacts").and_return(artifacts)
    allow(api).to receive(:list).with("#{path}/issues/9/comments").and_return(comments)
  end

  it "associates a fork run without a pull_requests payload through the current head" do
    expect(publisher.resolve).to include(number: 9, changed: true)
  end

  it "publishes only a fixed link, without downloading contributor artefacts" do
    expect(api).to receive(:request).with(
      "POST", "#{path}/issues/9/comments",
      {body: "#{described_class::MARKER}\n## Typing analysis\n[View the typing comparison and downloadable report](https://github.com/owner/project/actions/runs/100#summary).\n"},
    )

    publisher.publish
  end

  shared_examples "does not publish" do
    it "does not write a comment" do
      expect(api).not_to receive(:request)
      publisher.publish
    end
  end

  context "when another workflow copies the producer's name" do
    before { run["workflow_id"] = 8 }

    include_examples "does not publish"
  end

  context "when the producing event is not a pull request" do
    before { run["event"] = "push" }

    include_examples "does not publish"
  end

  context "when the run failed" do
    before { run["conclusion"] = "failure" }

    include_examples "does not publish"
  end

  context "when the run was retried since the callback" do
    before { run["run_attempt"] = 2 }

    include_examples "does not publish"
  end

  context "when the pull request has advanced" do
    before { pr["head"]["sha"] = "b" * 40 }

    include_examples "does not publish"
  end

  context "when another fork uses the same branch name and commit" do
    before { pr["head"]["repo"]["id"] = 21 }

    include_examples "does not publish"
  end

  context "when the commit belongs to multiple open pull requests" do
    let(:pulls) { [pr, pr.merge("number" => 10)] }

    include_examples "does not publish"
  end

  context "when a newer producer run exists for the same head" do
    let(:runs) { [run, run.merge("id" => 101, "status" => "in_progress")] }

    include_examples "does not publish"
  end

  context "when the report belongs to an earlier attempt" do
    let(:artifacts) { [{"name" => "typing-stats-0-changed", "expired" => false}] }

    include_examples "does not publish"
  end

  context "when the report expired" do
    let(:artifacts) { [{"name" => "typing-stats-1-changed", "expired" => true}] }

    include_examples "does not publish"
  end

  context "when contradictory reports were uploaded" do
    let(:artifacts) do
      [
        {"name" => "typing-stats-1-changed", "expired" => false},
        {"name" => "typing-stats-1-unchanged", "expired" => false},
      ]
    end

    include_examples "does not publish"
  end

  context "when the head changes between association and posting" do
    let(:fresh_pr) { pr.merge("head" => pr.fetch("head").merge("sha" => "b" * 40)) }

    include_examples "does not publish"
  end

  context "when a contributor copies the comment marker" do
    let(:comments) do
      [{"id" => 30, "body" => described_class::MARKER, "user" => {"login" => "contributor"}}]
    end

    it "creates its own comment instead of overwriting the contributor's" do
      expect(api).to receive(:request).with("POST", "#{path}/issues/9/comments", anything)
      publisher.publish
    end
  end

  context "when no typing changes were found" do
    let(:artifacts) { [{"name" => "typing-stats-1-unchanged", "expired" => false}] }

    include_examples "does not publish"

    context "with an existing comment from the publishing app" do
      let(:comments) do
        [{
          "id" => 31,
          "body" => described_class::MARKER,
          "user" => {"login" => "dd-octo-sts[bot]"},
          "performed_via_github_app" => {"slug" => "dd-octo-sts"},
        }]
      end

      it "updates its own comment to clear the previous changes" do
        expect(api).to receive(:request).with(
          "PATCH", "#{path}/issues/comments/31",
          {body: "#{described_class::MARKER}\n## Typing analysis\nThis PR does not change typing compared with the base branch.\n"},
        )
        publisher.publish
      end
    end
  end
end
