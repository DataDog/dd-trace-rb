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
  let(:batch) { workflow.fetch("jobs").fetch("batch") }
  let(:batch_steps) { batch.fetch("steps") }
  let(:prepare) { batch_steps.find { |step| step["uses"] == "./.github/actions/installed-bundle-cache" } }
  let(:lookup) { steps.find { |step| step["id"] == "lookup" } }
  let(:base) { steps.find { |step| step["id"] == "base-bundle" } }
  let(:population) { steps.find { |step| step["run"].to_s.include?("github:run_batch_build") } }
  let(:validation) { steps.find { |step| step["run"].to_s.include?("github:check_installed_bundle") } }
  let(:save) { steps.find { |step| step["uses"].to_s.start_with?("actions/cache/save@") } }

  it "uses an exact lookup-only parent probe without a restore prefix" do
    expect(lookup.fetch("with")).to include(
      "key" => "${{ steps.installed-key.outputs.cache-key }}",
      "lookup-only" => true,
      "path" => "/usr/local/bundle",
    )
    expect(lookup.fetch("with")).not_to have_key("restore-keys")
  end

  it "restores the computed base before population and validates the union before saving" do
    expect(base.fetch("uses")).to eq("./.github/actions/bundle-cache")
    expect(base.fetch("with").fetch("cache-key")).to eq("${{ steps.base-key.outputs.cache-key }}")
    expect(base.fetch("env").fetch("BUNDLE_GEMFILE")).to eq("${{ inputs.base-gemfile }}")
    expect(steps.index(base)).to be < steps.index(population)
    expect(steps.index(population)).to be < steps.index(validation)
    expect(steps.index(validation)).to be < steps.index(save)
  end

  it "includes the exact base cache key and generated Gemfile list in the union identity" do
    base_key = steps.find { |step| step["id"] == "base-key" }
    installed_key = steps.find { |step| step["id"] == "installed-key" }

    expect(base_key.fetch("env").fetch("IMAGE")).to eq("${{ inputs.image }}")
    expect(base_key.fetch("run")).to include("base-key", '--image-identity "$IMAGE"')
    expect(installed_key.fetch("env")).to include(
      "BASE_CACHE_KEY" => "${{ steps.base-key.outputs.cache-key }}",
      "GEMFILES" => "${{ inputs.gemfiles }}",
    )
    expect(installed_key.fetch("run")).to include(
      '--base-cache-key "$BASE_CACHE_KEY"',
      '--gemfiles "$GEMFILES"',
    )
    expect(installed_key.fetch("run")).not_to include("Matrixfile")
  end

  it "requires complete task and Gemfile lists from batch generation" do
    expect(action.fetch("inputs").fetch("tasks").fetch("required")).to be(true)
    expect(action.fetch("inputs").fetch("gemfiles").fetch("required")).to be(true)
    expect(prepare.fetch("with")).to include(
      "tasks" => "${{ steps.set-batches.outputs.all }}",
      "gemfiles" => "${{ steps.set-batches.outputs.gemfiles }}",
    )

    batches = batch_steps.find { |step| step["id"] == "set-batches" }
    run = batches.fetch("run")

    %w[all gemfiles].each do |output|
      expect(run).to include("[\"#{output}\"].to_json")
      expect(run).to match(/echo "#{output}=\$\w+"/)
    end
    expect(run).to include('>> "$GITHUB_OUTPUT"')
  end

  it "populates through existing batch installation and checks all selected Gemfiles" do
    expect(population.fetch("run")).to eq("bundle exec rake github:run_batch_build")
    expect(population.fetch("env").fetch("BATCHED_TASKS")).to eq("${{ inputs.tasks }}")
    expect(validation.fetch("run")).to eq("bundle exec rake github:check_installed_bundle")
    expect(validation.fetch("env")).to include(
      "GEMFILES" => "${{ inputs.gemfiles }}",
      "BUNDLE_GEMFILE" => "${{ inputs.base-gemfile }}",
    )
  end

  it "reports whether the exact cache is ready" do
    expect(action.fetch("outputs").fetch("ready").fetch("value")).to eq(
      "${{ steps.lookup.outputs.cache-hit == 'true' || inputs.write-enabled == 'true' }}",
    )
  end

  it "prepares the lean base only after an exact union miss" do
    expect(steps.index(lookup)).to be < steps.index(base)
    expect(base.fetch("if")).to eq("steps.lookup.outputs.cache-hit != 'true'")
  end

  it "populates, validates, and saves only on a writable exact miss" do
    [population, validation, save].each do |step|
      expect(step.fetch("if")).to eq(
        "steps.lookup.outputs.cache-hit != 'true' && inputs.write-enabled == 'true'",
      )
    end
    expect(save.fetch("with")).to include(
      "key" => "${{ steps.installed-key.outputs.cache-key }}",
      "path" => "/usr/local/bundle",
    )
    expect(save.fetch("with")).not_to have_key("restore-keys")
  end

  it "routes a union miss directly to the prepared base outputs" do
    expect(batch.fetch("outputs")).to include(
      "cache-key" => "${{ steps.installed-bundle-cache.outputs.base-cache-key }}",
      "lockfile" => "${{ steps.installed-bundle-cache.outputs.base-lockfile }}",
      "installed-cache-key" => "${{ steps.installed-bundle-cache.outputs.cache-key }}",
      "installed-cache-ready" => "${{ steps.installed-bundle-cache.outputs.ready }}",
    )
    expect(batch_steps).not_to include(include("uses" => "./.github/actions/bundle-cache"))
  end

  it "generates batches and summary without Bundler before cache preparation" do
    batches = batch_steps.find { |step| step["id"] == "set-batches" }
    summary = batch_steps.find { |step| step["run"].to_s.include?("github:generate_batch_summary") }

    expect(batches.fetch("run")).to include("rake -f tasks/github.rake github:generate_batches")
    expect(batches.fetch("run")).not_to include("bundle exec")
    expect(summary.fetch("run")).to eq("rake -f tasks/github.rake github:generate_batch_summary")
    expect(summary.fetch("env").fetch("batches_json")).to eq("${{ steps.set-batches.outputs.batches }}")
    expect(batch_steps.index(batches)).to be < batch_steps.index(summary)
    expect(batch_steps.index(summary)).to be < batch_steps.index(prepare)
  end

  it "always prepares batch dependencies before tests regardless of cache readiness" do
    build_steps = build_action.fetch("runs").fetch("steps")
    install = build_steps.find { |step| step["run"].to_s.include?("github:run_batch_build") }
    tests = build_steps.find { |step| step["run"].to_s.include?("github:run_batch_tests") }

    expect(build_action.fetch("inputs")).not_to have_key("install-dependencies")
    expect(install.fetch("run")).to eq("bundle exec rake github:run_batch_build")
    expect(install).not_to have_key("if")
    expect(build_steps.index(install)).to be < build_steps.index(tests)
    expect(build_steps).not_to include(include("run" => include("github:check_installed_bundle")))
  end

  it "restores the exact union in ready children and the lean base otherwise" do
    jobs = workflow.fetch("jobs")

    %w[build-test-standard build-test-misc].each do |job_name|
      child_steps = jobs.fetch(job_name).fetch("steps")
      base_restore = child_steps.find { |step| step["uses"] == "./.github/actions/bundle-restore" }
      installed = child_steps.find { |step| step["uses"].to_s.start_with?("actions/cache/restore@") }
      build = child_steps.find { |step| step["uses"] == "./.github/actions/build-test" }

      expect(base_restore.fetch("if")).to eq("needs.batch.outputs.installed-cache-ready != 'true'")
      expect(base_restore.fetch("with")).to include(
        "lockfile" => "${{ needs.batch.outputs.lockfile }}",
        "cache-key" => "${{ needs.batch.outputs.cache-key }}",
      )
      expect(installed.fetch("if")).to eq("needs.batch.outputs.installed-cache-ready == 'true'")
      expect(installed.fetch("with")).to include(
        "key" => "${{ needs.batch.outputs.installed-cache-key }}",
        "path" => "/usr/local/bundle",
        "fail-on-cache-miss" => true,
      )
      expect(installed.fetch("with")).not_to have_key("restore-keys")
      expect(installed.fetch("with")).not_to have_key("lookup-only")
      expect(build.fetch("with")).not_to have_key("install-dependencies")
      expect(child_steps.index(base_restore)).to be < child_steps.index(build)
      expect(child_steps.index(installed)).to be < child_steps.index(build)
      expect(child_steps).not_to include(include("run" => include("github:check_installed_bundle")))
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
    expect(runtime_jobs.values).to all(include("with" => include("engine" => "ruby")))
  end

  it "uses the same engine image in the parent, cache, and children" do
    jobs = workflow.fetch("jobs")
    batch_image = batch.fetch("container").fetch("image")

    expect(prepare.fetch("with").fetch("image")).to eq(batch_image)
    expect(jobs.fetch("build-test-standard").fetch("container").fetch("image")).to eq(batch_image)
    expect(jobs.fetch("build-test-misc").fetch("container").fetch("image")).to eq(batch_image)
  end

  it "permits writes only from master" do
    expect(prepare.fetch("with").fetch("write-enabled")).to eq(
      "${{ github.ref == 'refs/heads/master' }}",
    )
  end
end
