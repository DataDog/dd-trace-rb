require "spec_helper"
require "open3"
require "tempfile"
require "yaml"

RSpec.describe "installed bundle cache workflow" do
  let(:action) do
    YAML.safe_load_file(
      File.expand_path("../../.github/actions/installed-bundle-cache/action.yml", __dir__),
      aliases: true,
    )
  end
  let(:restore_action) do
    YAML.safe_load_file(
      File.expand_path("../../.github/actions/installed-bundle-restore/action.yml", __dir__),
      aliases: true,
    )
  end
  let(:workflow) do
    YAML.safe_load_file(
      File.expand_path("../../.github/workflows/_unit_test.yml", __dir__),
      aliases: true,
    )
  end
  let(:steps) { action.fetch("runs").fetch("steps") }

  def run_output(script, environment)
    Tempfile.create do |output|
      env = environment.merge("GITHUB_OUTPUT" => output.path)
      _stdout, stderr, status = Open3.capture3(env, "bash", "-c", script)
      raise stderr unless status.success?

      File.readlines(output.path, chomp: true).to_h { |line| line.split("=", 2) }
    end
  end

  it "uses a lookup-only parent probe" do
    lookup = steps.find { |step| step["id"] == "lookup" }

    expect(lookup.fetch("with")).to include(
      "lookup-only" => true,
      "path" => "/usr/local/bundle",
    )
  end

  it "validates a generated union before saving it" do
    names = steps.map { |step| step["name"] }

    expect(names.index("Verify complete matrix bundle")).to be < names.index("Save installed bundle")
  end

  it "classifies exact, writable miss, and read-only miss states" do
    result = steps.find { |step| step["id"] == "result" }.fetch("run")

    expect(run_output(result, "EXACT_HIT" => "true", "WRITE_ENABLED" => "false")).to include(
      "status" => "exact",
      "ready" => "true",
    )
    expect(run_output(result, "EXACT_HIT" => "false", "WRITE_ENABLED" => "true")).to include(
      "status" => "generated",
      "ready" => "true",
    )
    expect(run_output(result, "EXACT_HIT" => "false", "WRITE_ENABLED" => "false")).to include(
      "status" => "miss",
      "ready" => "false",
    )
  end

  it "contains no strategy selector or grouped cache lifecycle" do
    source = File.read(File.expand_path("../../.github/workflows/_unit_test.yml", __dir__))

    expect(source).not_to include("installed-cache-strategy", "group-delta", "group-full", "all-delta")
    expect(source).not_to include("package-cache", "minimal-tests", "experiment-variant")
  end

  it "does not prepare the base cache before an installed-cache lookup" do
    batch_steps = workflow.fetch("jobs").fetch("batch").fetch("steps")
    base = batch_steps.find { |step| step["name"] == "Prepare bundle cache" }
    fallback = batch_steps.find { |step| step["name"] == "Prepare fallback bundle cache" }

    expect(base.fetch("if")).to eq("inputs.installed-cache-enabled != true")
    expect(fallback.fetch("if")).to include("outputs.ready != 'true'")
  end

  it "maps fallback tasks to the committed runtime Gemfile" do
    batch_steps = workflow.fetch("jobs").fetch("batch").fetch("steps")
    batches = batch_steps.find { |step| step["name"] == "Distribute tasks into batches" }

    expect(batches.fetch("env").fetch("FALLBACK_GEMFILE")).to include(
      "gemfiles/{0}-{1}.gemfile",
      "inputs.installed-cache-enabled",
    )
  end

  it "restores one exact union in each ready child" do
    jobs = workflow.fetch("jobs")

    %w[build-test-standard build-test-misc].each do |job_name|
      child_steps = jobs.fetch(job_name).fetch("steps")
      base = child_steps.find { |step| step["name"] == "Restore bundle cache" }
      installed = child_steps.find { |step| step["name"] == "Restore installed matrix bundle" }
      build = child_steps.find { |step| step["name"] == "Build & Test" }

      expect(base.fetch("if")).to include("installed-cache-ready != 'true'")
      expect(installed.fetch("if")).to include("installed-cache-ready == 'true'")
      expect(installed.fetch("with").fetch("cache-key")).to include("installed-cache-key")
      expect(build.fetch("with").fetch("install-dependencies")).to include("installed-cache-ready != 'true'")
    end
  end

  it "restores only the complete installed path and fails on a miss" do
    restore = restore_action.fetch("runs").fetch("steps").find do |step|
      step["name"] == "Restore installed bundle"
    end

    expect(restore.fetch("with")).to include(
      "path" => "/usr/local/bundle",
      "fail-on-cache-miss" => true,
    )
  end
end
