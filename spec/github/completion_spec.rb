# frozen_string_literal: true

require "json"
require "open3"
require "yaml"
require "spec_helper"

RSpec.describe "CI completion checks" do
  def complete(workflow, results)
    job = YAML.safe_load(File.read(".github/workflows/#{workflow}"), aliases: true).fetch("jobs").fetch("complete")
    command = job.fetch("steps").first.fetch("run")
    _, error, status = Open3.capture3({"RESULTS" => JSON.generate(results)}, "bash", "-e", "-o", "pipefail", "-c", command)
    raise error unless error.empty?

    status.success?
  end

  [
    "build-gem.yml", "check.yml", "codeql-analysis.yml", "integration-test.yml",
    "nix.yml", "test-macos.yaml", "test-memory-leaks.yaml", "test-yjit.yaml", "test.yml",
  ].each do |workflow|
    context workflow do
      it "accepts successful validation" do
        expect(complete(workflow, {"test" => {"result" => "success"}})).to be true
      end

      ["failure", "cancelled", "skipped"].each do |result|
        it "rejects a #{result} dependency" do
          expect(complete(workflow, {"test" => {"result" => result}})).to be false
        end
      end

      it "rejects an empty dependency result" do
        expect(complete(workflow, {})).to be false
      end
    end
  end

  [
    ["system-tests.yml", "changes", ["build", "test"]],
    ["lock-dependency.yml", "dependency", ["lock"]],
  ].each do |workflow, detector, jobs|
    context workflow do
      let(:results) do
        {detector => {"result" => "success", "outputs" => {"changes" => "false"}}}
          .merge(jobs.map { |name| [name, {"result" => "skipped"}] }.to_h)
      end

      it "accepts an intentional path-based skip" do
        expect(complete(workflow, results)).to be true
      end

      it "rejects skipped validation when changes were detected" do
        results[detector]["outputs"]["changes"] = "true"
        expect(complete(workflow, results)).to be false
      end

      it "rejects a failed change detector" do
        results[detector]["result"] = "failure"
        expect(complete(workflow, results)).to be false
      end

      it "rejects a missing change decision" do
        results[detector]["outputs"] = {}
        expect(complete(workflow, results)).to be false
      end

      it "accepts successful selected validation" do
        results[detector]["outputs"]["changes"] = "true"
        jobs.each { |name| results[name]["result"] = "success" }
        expect(complete(workflow, results)).to be true
      end
    end
  end
end
