# frozen_string_literal: true

require_relative "github"

module CI
  class TypingComment
    MARKER = "<!-- TYPING_STATS_HIDDEN_MARKER -->"
    WORKFLOW = ".github/workflows/typing-stats.yml"

    def initialize(api, repository, event)
      @api = api
      @repository = repository
      @event = event
      @path = "repos/#{repository}"
    end

    def resolve
      run = @api.get("#{@path}/actions/runs/#{Integer(@event.fetch("id"))}")
      workflow = @api.get("#{@path}/actions/workflows/typing-stats.yml")
      return unless run["workflow_id"] == workflow.fetch("id") && run["path"] == WORKFLOW
      return unless run["event"] == "pull_request" && run["status"] == "completed" && run["conclusion"] == "success"
      return unless run.dig("repository", "full_name") == @repository
      return unless run["head_sha"] == @event.fetch("head_sha") && run["run_attempt"] == @event.fetch("run_attempt")
      return unless run.dig("head_repository", "id")

      pulls = @api.list("#{@path}/commits/#{run.fetch("head_sha")}/pulls").select { |pr| current?(pr, run) }
      return unless pulls.size == 1

      latest = @api.list("#{@path}/actions/workflows/typing-stats.yml/runs?event=pull_request&head_sha=#{run.fetch("head_sha")}", key: "workflow_runs")
        .select { |candidate| candidate.dig("head_repository", "id") == run.dig("head_repository", "id") && candidate["head_branch"] == run["head_branch"] }
        .max_by { |candidate| candidate.fetch("id") }
      return unless latest && latest["id"] == run["id"]

      names = ["typing-stats-#{run.fetch("run_attempt")}-changed", "typing-stats-#{run.fetch("run_attempt")}-unchanged"]
      reports = @api.list("#{@path}/actions/runs/#{run.fetch("id")}/artifacts", key: "artifacts")
        .select { |artifact| names.include?(artifact["name"]) && artifact["expired"] == false }
      return unless reports.size == 1

      {number: pulls.first.fetch("number"), changed: reports.first.fetch("name") == names.first, run: run}
    end

    def publish
      report = resolve
      return unless report

      comments = @api.list("#{@path}/issues/#{report.fetch(:number)}/comments")
      comment = comments.find do |entry|
        entry.dig("user", "login") == "dd-octo-sts[bot]" &&
          entry.dig("performed_via_github_app", "slug") == "dd-octo-sts" &&
          entry.fetch("body").start_with?(MARKER)
      end
      return unless report.fetch(:changed) || comment

      pr = @api.get("#{@path}/pulls/#{report.fetch(:number)}")
      return unless current?(pr, report.fetch(:run))

      url = "https://github.com/#{@repository}/actions/runs/#{report.fetch(:run).fetch("id")}"
      message = if report.fetch(:changed)
        "[View the typing comparison and downloadable report](#{url}#summary)."
      else
        "This PR does not change typing compared with the base branch."
      end
      body = {body: "#{MARKER}\n## Typing analysis\n#{message}\n"}

      if comment
        @api.request("PATCH", "#{@path}/issues/comments/#{comment.fetch("id")}", body)
      else
        @api.request("POST", "#{@path}/issues/#{report.fetch(:number)}/comments", body)
      end
    end

    private

    def current?(pr, run)
      pr["state"] == "open" && pr.dig("base", "repo", "full_name") == @repository &&
        pr.dig("head", "sha") == run["head_sha"] &&
        pr.dig("head", "repo", "id") == run.dig("head_repository", "id") &&
        pr.dig("head", "ref") == run["head_branch"]
    end
  end
end

if $PROGRAM_NAME == __FILE__
  mode, repository, event_path, output = ARGV
  event = JSON.parse(File.read(event_path)).fetch("workflow_run")
  publisher = CI::TypingComment.new(CI::GitHub.new, repository, event)
  case mode
  when "verify"
    ready = !publisher.resolve.nil?
    File.open(output, "a") { |file| file.puts("ready=#{ready}") }
    puts(ready ? "Found a current typing report." : "No current, unambiguous typing report to publish.")
  when "publish"
    publisher.publish
  else
    abort "Expected verify or publish"
  end
end
