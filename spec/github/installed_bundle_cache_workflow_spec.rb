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

  it "restores the base before installing appraisals and validates the union before saving" do
    names = steps.map { |step| step["name"] }

    expect(names.index("Prepare lean base bundle")).to be < names.index("Install appraisal bundles")
    expect(names.index("Verify complete matrix bundle")).to be < names.index("Save installed bundle")
  end

  it "includes the exact base cache key in the union manifest" do
    base_key = steps.find { |step| step["id"] == "base-key" }
    manifest = steps.find { |step| step["id"] == "manifest" }

    expect(base_key.fetch("env").fetch("LOCKFILE_HASH")).to include("hashFiles")
    expect(manifest.fetch("env").fetch("BASE_CACHE_KEY")).to include("steps.base-key.outputs.cache-key")
    expect(manifest.fetch("run")).to include('--base-cache-key "$BASE_CACHE_KEY"')
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

  it "does not restore the base before an exact union lookup" do
    lookup_index = steps.index { |step| step["id"] == "lookup" }
    base_index = steps.index { |step| step["id"] == "base-bundle" }
    base = steps.fetch(base_index)

    expect(lookup_index).to be < base_index
    expect(base.fetch("if")).to eq("steps.lookup.outputs.cache-hit != 'true'")
  end

  it "routes a union miss directly to the prepared base outputs" do
    batch = workflow.fetch("jobs").fetch("batch")
    outputs = batch.fetch("outputs")
    batch_steps = batch.fetch("steps")

    expect(outputs.fetch("cache-key")).to include("installed-bundle-cache.outputs.base-cache-key")
    expect(outputs.fetch("lockfile")).to include("installed-bundle-cache.outputs.base-lockfile")
    expect(batch_steps).not_to include(include("name" => "Prepare fallback bundle cache"))
  end

  it "maps fallback tasks to the committed runtime Gemfile" do
    batch_steps = workflow.fetch("jobs").fetch("batch").fetch("steps")
    batches = batch_steps.find { |step| step["name"] == "Distribute tasks into batches" }
    summary = batch_steps.find { |step| step["name"] == "Generate batch summary" }

    expect(batches.fetch("env").fetch("FALLBACK_GEMFILE")).to include(
      "gemfiles/{0}-{1}.gemfile",
      "inputs.installed-cache-enabled",
    )
    expect(batches.fetch("run")).to include("rake -f tasks/github.rake")
    expect(batches.fetch("run")).not_to include("bundle exec")
    expect(summary.fetch("run")).to eq("rake -f tasks/github.rake github:generate_batch_summary")
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
      expect(child_steps.count { |step| step["uses"] == "./.github/actions/bundle-restore" }).to eq(1)
      expect(child_steps.count { |step| step["uses"] == "./.github/actions/installed-bundle-restore" }).to eq(1)
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
