# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"
require "spec_helper"

RSpec.describe "CI source provenance" do
  around do |example|
    Dir.mktmpdir("ci-provenance") do |directory|
      @directory = directory
      example.run
    end
  end

  def executable(name, source)
    path = File.join(@directory, name)
    File.write(path, "#!#{RbConfig.ruby}\n#{source}")
    FileUtils.chmod(0o755, path)
  end

  def run_script(script, environment = {})
    Open3.capture3({"PATH" => "#{@directory}:#{ENV.fetch("PATH")}"}.merge(environment), "bash", ".github/scripts/#{script}")
  end

  describe "release exemptions" do
    before { executable("git", 'puts "CHANGELOG.md"') }

    def check_changelog(repository, branch)
      _, _, status = run_script("check_changelog_release_only.sh", {
        "GITHUB_REPOSITORY" => "owner/project",
        "HEAD_REPOSITORY" => repository,
        "HEAD_REF" => branch,
        "BASE_REF" => "master",
        "PR_HEAD_SHA" => "a" * 40,
      })
      status.success?
    end

    ["bump_to_version_2.47.0", "changelog_fix_format"].each do |branch|
      it "rejects a fork's #{branch} exemption" do
        expect(check_changelog("contributor/project", branch)).to be false
      end

      it "accepts the upstream #{branch} exemption" do
        expect(check_changelog("owner/project", branch)).to be true
      end
    end

    it "fails closed when source repository metadata is absent" do
      expect(check_changelog("", "bump_to_version_2.47.0")).to be false
    end
  end

  describe "timing artefact selection" do
    let(:upstream) { {"full_name" => "owner/project"} }
    let(:run) do
      {"id" => 1, "event" => "push", "conclusion" => "success", "path" => ".github/workflows/test.yml",
       "head_branch" => "master", "repository" => upstream, "head_repository" => upstream}
    end
    let(:runs) do
      [
        run,
        run.merge("id" => 2, "event" => "pull_request", "head_repository" => {"full_name" => "contributor/project"}),
        run.merge("id" => 3, "head_repository" => {"full_name" => "contributor/project"}),
        run.merge("id" => 4, "event" => "workflow_dispatch"),
        run.merge("id" => 5, "head_branch" => "other"),
        run.merge("id" => 6, "path" => ".github/workflows/other.yml"),
        run.merge("id" => 7, "conclusion" => "failure"),
      ]
    end

    it "downloads only successful upstream pushes, even when other runs claim the master branch" do
      calls = File.join(@directory, "calls.jsonl")
      response = File.join(@directory, "response.json")
      File.write(response, JSON.generate("workflow_runs" => runs))
      executable("gh", <<~RUBY)
        require "json"
        File.open(#{calls.inspect}, "a") { |file| file.puts(JSON.generate(ARGV)) }
        puts File.read(#{response.inspect}) if ARGV.first == "api"
      RUBY

      _, error, status = Open3.capture3(
        {"PATH" => "#{@directory}:#{ENV.fetch("PATH")}", "GITHUB_REPOSITORY" => "owner/project"},
        "bash", ".github/scripts/download_timing_artifacts.sh", File.join(@directory, "timings"),
      )
      expect(status.success?).to be(true), error
      downloads = File.readlines(calls).map { |line| JSON.parse(line) }.select { |arguments| arguments.first == "run" }
      expect(downloads.map { |arguments| arguments.fetch(2) }).to eq(["1"])
    end
  end
end
