require "spec_helper"
require "yaml"

RSpec.describe "installed bundle cache workflow" do
  let(:action) do
    YAML.safe_load_file(
      File.expand_path("../../.github/actions/installed-bundle-cache/action.yml", __dir__),
      aliases: true,
    )
  end
  let(:workflow) do
    YAML.safe_load_file(
      File.expand_path("../../.github/workflows/_unit_test.yml", __dir__),
      aliases: true,
    )
  end
  let(:build_action) do
    YAML.safe_load_file(
      File.expand_path("../../.github/actions/build-test/action.yml", __dir__),
      aliases: true,
    )
  end
  let(:production_workflow) do
    YAML.safe_load_file(
      File.expand_path("../../.github/workflows/test.yml", __dir__),
      aliases: true,
    )
  end
  let(:steps) { action.fetch("runs").fetch("steps") }

  it "uses a lookup-only parent probe" do
    lookup = steps.find { |step| step["id"] == "lookup" }

    expect(lookup.fetch("with")).to include(
      "lookup-only" => true,
      "path" => "/usr/local/bundle",
    )
  end

  it "restores the computed base before installing appraisals and validates the union before saving" do
    names = steps.map { |step| step["name"] }
    base = steps.find { |step| step["name"] == "Prepare lean base bundle" }

    expect(base.fetch("with").fetch("cache-key")).to include("steps.base-key.outputs.cache-key")
    expect(names.index("Prepare lean base bundle")).to be < names.index("Install appraisal bundles")
    expect(names.index("Verify complete matrix bundle")).to be < names.index("Save installed bundle")
  end

  it "includes the exact base cache key in the union identity" do
    base_key = steps.find { |step| step["id"] == "base-key" }
    installed_key = steps.find { |step| step["id"] == "installed-key" }

    expect(base_key.fetch("env").fetch("IMAGE")).to eq("${{ inputs.image }}")
    expect(base_key.fetch("run")).to include("base-key", '--image-identity "${IMAGE##*/}"')
    expect(installed_key.fetch("env").fetch("BASE_CACHE_KEY")).to include("steps.base-key.outputs.cache-key")
    expect(installed_key.fetch("run")).to include('--base-cache-key "$BASE_CACHE_KEY"')
  end

  it "reports whether the exact cache is ready" do
    expect(action.fetch("outputs").fetch("ready").fetch("value")).to eq(
      "${{ steps.lookup.outputs.cache-hit == 'true' || inputs.write-enabled == 'true' }}",
    )
  end

  it "does not restore the base before an exact union lookup" do
    lookup_index = steps.index { |step| step["id"] == "lookup" }
    base_index = steps.index { |step| step["id"] == "base-bundle" }
    base = steps.fetch(base_index)

    expect(lookup_index).to be < base_index
    expect(base.fetch("if")).to eq("steps.lookup.outputs.cache-hit != 'true'")
  end

  it "skips base preparation, population, validation, and save on an exact hit" do
    miss_only_steps = steps.select do |step|
      step["id"] == "base-bundle" ||
        step["name"] == "Install appraisal bundles" ||
        step["name"] == "Verify complete matrix bundle" ||
        step["name"] == "Save installed bundle"
    end

    expect(miss_only_steps.length).to eq(4)
    expect(miss_only_steps).to all(include("if" => include("steps.lookup.outputs.cache-hit != 'true'")))
  end

  it "skips population, validation, and save on a read-only miss" do
    writable_steps = steps.select do |step|
      step["name"] == "Install appraisal bundles" ||
        step["name"] == "Verify complete matrix bundle" ||
        step["name"] == "Save installed bundle"
    end

    expect(writable_steps.length).to eq(3)
    expect(writable_steps).to all(include("if" => include("inputs.write-enabled == 'true'")))
  end

  it "routes a union miss directly to the prepared base outputs" do
    batch = workflow.fetch("jobs").fetch("batch")
    outputs = batch.fetch("outputs")
    batch_steps = batch.fetch("steps")

    expect(outputs.fetch("cache-key")).to include("installed-bundle-cache.outputs.base-cache-key")
    expect(outputs.fetch("lockfile")).to include("installed-bundle-cache.outputs.base-lockfile")
    expect(batch_steps).not_to include(include("name" => "Prepare bundle cache"))
  end

  it "runs bootstrap tasks without Bundler" do
    batch_steps = workflow.fetch("jobs").fetch("batch").fetch("steps")
    batches = batch_steps.find { |step| step["name"] == "Distribute tasks into batches" }
    summary = batch_steps.find { |step| step["name"] == "Generate batch summary" }

    expect(batches.fetch("run")).to include("rake -f tasks/github.rake github:generate_batches")
    expect(summary.fetch("run")).to eq("rake -f tasks/github.rake github:generate_batch_summary")
  end

  it "skips batch dependency installation when the union is ready" do
    install = build_action.fetch("runs").fetch("steps").find do |step|
      step["name"] == "Install batch dependencies"
    end

    expect(install).to include(
      "if" => "inputs.install-dependencies == 'true'",
      "run" => "bundle exec rake github:run_batch_build",
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
      expect(installed.fetch("with").fetch("key")).to include("installed-cache-key")
      expect(build.fetch("with").fetch("install-dependencies")).to include("installed-cache-ready != 'true'")
      expect(child_steps.count { |step| step["uses"] == "./.github/actions/bundle-restore" }).to eq(1)
      expect(child_steps.count { |step| step["uses"].to_s.start_with?("actions/cache/restore@") }).to eq(1)
    end
  end

  it "uses the installed cache workflow for every production Ruby version" do
    jobs = production_workflow.fetch("jobs")
    runtime_jobs = jobs.select { |_name, job| job["uses"] == "./.github/workflows/_unit_test.yml" }

    expect(runtime_jobs.keys).to contain_exactly(
      "ruby-40",
      "ruby-34",
      "ruby-33",
      "ruby-32",
      "ruby-31",
      "ruby-30",
      "ruby-27",
      "ruby-26",
      "ruby-25",
    )
  end

  it "uses the same engine image in the parent, cache, and children" do
    jobs = workflow.fetch("jobs")
    batch_image = jobs.fetch("batch").fetch("container").fetch("image")
    prepare = jobs.fetch("batch").fetch("steps").find do |step|
      step["name"] == "Prepare installed matrix bundle cache"
    end

    expect(prepare.fetch("with").fetch("image")).to eq(batch_image)
    expect(jobs.fetch("build-test-standard").fetch("container").fetch("image")).to eq(batch_image)
    expect(jobs.fetch("build-test-misc").fetch("container").fetch("image")).to eq(batch_image)
  end

  it "permits writes only from the default branch" do
    prepare = workflow.fetch("jobs").fetch("batch").fetch("steps").find do |step|
      step["name"] == "Prepare installed matrix bundle cache"
    end

    expect(prepare.fetch("with").fetch("write-enabled")).to eq(
      "${{ github.ref == 'refs/heads/master' }}",
    )
  end

  it "uses the same complete installed path for lookup, save, and restore" do
    lookup = steps.find { |step| step["id"] == "lookup" }
    save = steps.find { |step| step["name"] == "Save installed bundle" }
    restore = workflow.fetch("jobs").fetch("build-test-standard").fetch("steps").find do |step|
      step["name"] == "Restore installed matrix bundle"
    end

    expect(lookup.fetch("with").fetch("path")).to eq("/usr/local/bundle")
    expect(save.fetch("with").fetch("path")).to eq("/usr/local/bundle")
    expect(restore.fetch("with")).to include(
      "path" => "/usr/local/bundle",
      "fail-on-cache-miss" => true,
    )
  end
end
