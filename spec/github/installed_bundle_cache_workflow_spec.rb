require "spec_helper"
require "open3"
require "tempfile"
require "yaml"

RSpec.describe "partitioned installed bundle cache workflow" do
  let(:group_action) do
    YAML.safe_load_file(
      File.expand_path("../../.github/actions/installed-bundle-group-cache/action.yml", __dir__),
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
  let(:group_steps) { group_action.fetch("runs").fetch("steps") }
  let(:restore_steps) { restore_action.fetch("runs").fetch("steps") }

  def run_output(script, environment)
    Tempfile.create do |output|
      env = environment.merge("GITHUB_OUTPUT" => output.path)
      _stdout, stderr, status = Open3.capture3(env, "bash", "-c", script)
      raise stderr unless status.success?

      File.readlines(output.path, chomp: true).to_h { |line| line.split("=", 2) }
    end
  end

  def lifecycle(overrides = {})
    step = group_steps.find { |candidate| candidate["id"] == "lifecycle" }
    environment = %w[STANDARD_0 STANDARD_1 STANDARD_2 STANDARD_3 STANDARD_4 STANDARD_5 STANDARD_6 MISC_0].each_with_object(
      {"BASE_HIT" => "true"}
    ) do |name, values|
      values["#{name}_HIT"] = "true"
    end

    run_output(step.fetch("run"), environment.merge(overrides))
  end

  it "has one fixed installed-cache architecture" do
    call_inputs = workflow.fetch(true).fetch("workflow_call").fetch("inputs")
    dispatch_inputs = workflow.fetch(true).fetch("workflow_dispatch").fetch("inputs")

    expect(call_inputs).to include("installed-cache-enabled", "installed-cache-write")
    expect(dispatch_inputs).to include("installed-cache-enabled", "installed-cache-write")
    expect(call_inputs).not_to include("installed-cache-strategy", "installed-cache-key-variant")
  end

  it "rejects installed-cache use outside Ruby 4.0" do
    step = workflow.fetch("jobs").fetch("batch").fetch("steps").find do |candidate|
      candidate["name"] == "Validate installed cache runtime"
    end

    expect(step.fetch("if")).to include(
      "inputs.installed-cache-enabled",
      "inputs.engine != 'ruby'",
      "inputs.version != '4.0'",
    )
  end

  it "preserves baseline cache lifecycle when installed caching is disabled" do
    jobs = workflow.fetch("jobs")
    parent_restore = jobs.fetch("batch").fetch("steps").find { |step| step["name"] == "Prepare bundle cache" }

    expect(parent_restore.fetch("if")).to eq("inputs.installed-cache-enabled != true")
    %w[build-test-standard build-test-misc].each do |job_name|
      child_restore = jobs.fetch(job_name).fetch("steps").find { |step| step["name"] == "Restore bundle cache" }
      expect(child_restore.fetch("if")).to eq("inputs.installed-cache-enabled != true")
    end
  end

  it "computes group manifests after distributing tasks" do
    steps = workflow.fetch("jobs").fetch("batch").fetch("steps")
    names = steps.map { |step| step["name"] }
    grouped = steps.find { |step| step["name"] == "Prepare partitioned installed bundle caches" }

    expect(names.index("Distribute tasks into batches")).to be < names.index(grouped.fetch("name"))
    expect(grouped.fetch("with")).to include(
      "standard-groups" => include("steps.set-batches.outputs.batches"),
      "misc-groups" => include("steps.set-batches.outputs.misc"),
    )
  end

  it "makes every parent cache lookup writable-only" do
    lookups = group_steps.select do |step|
      step.fetch("with", {}).fetch("lookup-only", false) == true
    end

    expect(lookups.size).to eq(9)
    expect(lookups).to all(include("if" => include("inputs.write-enabled == 'true'")))
  end

  it "uses lookup-only probes before base materialization" do
    names = group_steps.map { |step| step["name"] }
    lookups = group_steps.select do |step|
      step.fetch("with", {}).fetch("lookup-only", false) == true
    end
    base_restore = group_steps.find { |step| step["name"] == "Restore installed base bundle for generation" }
    preserve = group_steps.find { |step| step["name"] == "Preserve installed base bundle" }

    expect(lookups).to all(include("with" => include("lookup-only" => true)))
    expect(names.index("Look up misc-0 installed bundle")).to be < names.index(base_restore.fetch("name"))
    expect(base_restore.fetch("if")).to include("generation-needed")
    expect(preserve.fetch("if")).to include("generation-needed")
  end

  it "does not request generation when base and all groups exist" do
    expect(lifecycle).to include("base-missing" => "false", "generation-needed" => "false")
  end

  it "requests generation when one group is absent" do
    expect(lifecycle("STANDARD_3_HIT" => "false")).to include(
      "base-missing" => "false",
      "generation-needed" => "true",
    )
  end

  it "repairs a missing base independently from group generation" do
    expect(lifecycle("BASE_HIT" => "false")).to include(
      "base-missing" => "true",
      "generation-needed" => "false",
    )
  end

  it "saves only missing group partitions after one union generation" do
    generation = group_steps.find { |step| step["name"] == "Prepare partitioned installed bundle groups" }
    saves = group_steps.select { |step| step.fetch("name", "").start_with?("Save standard-", "Save misc-") }

    expect(generation.fetch("run")).to include("prepare-partitioned-groups")
    expect(saves.size).to eq(8)
    expect(saves).to all(include("if" => include("generation-needed", "cache-hit != 'true'")))
  end

  it "starts child timing before base restore and path computation" do
    ids = restore_steps.map { |step| step["id"] }

    expect(ids.index("start")).to be < ids.index("restore-base")
    expect(ids.index("start")).to be < ids.index("group-paths")
    expect(restore_action.fetch("outputs").fetch("restore-seconds").fetch("description")).to include(
      "Base restore",
      "path computation",
    )
  end

  it "installs base only when its exact cache is absent" do
    install = restore_steps.find { |step| step["name"] == "Install missing base bundle" }

    expect(install.fetch("if")).to eq("steps.restore-base.outputs.cache-hit != 'true'")
    expect(install.fetch("env")).to include("BUNDLE_GEMFILE" => include("inputs.base-gemfile"))
  end

  it "restores only the exact child group directly to computed paths" do
    paths = restore_steps.find { |step| step["id"] == "group-paths" }
    restore = restore_steps.find { |step| step["id"] == "restore" }

    expect(paths.fetch("run")).to include("cache-paths")
    expect(restore.fetch("with")).to include(
      "key" => include("inputs.cache-key"),
      "path" => include("steps.group-paths.outputs.value"),
    )
    expect(restore.fetch("with")).not_to include("restore-keys", "fail-on-cache-miss")
  end

  it "lets each child miss control only that child's dependency install" do
    jobs = workflow.fetch("jobs")

    %w[build-test-standard build-test-misc].each do |job_name|
      steps = jobs.fetch(job_name).fetch("steps")
      restore = steps.find { |step| step["name"] == "Restore partitioned installed bundle" }
      build = steps.find { |step| step["name"] == "Build & Test" }

      expect(restore.fetch("with").fetch("cache-key")).to include(
        "env.INSTALLED_CACHE_GROUP_KIND",
        "matrix.batch",
      )
      expect(build.fetch("with").fetch("install-dependencies")).to include(
        "steps.installed-bundle-restore.outputs.exact-hit != 'true'"
      )
    end
  end

  it "keeps aggregate group status out of child conditions" do
    source = File.read(File.expand_path("../../.github/workflows/_unit_test.yml", __dir__))

    expect(source).not_to include("installed-cache-status", "installed-cache-ready")
  end

  it "keeps discarded cache experiments out of production workflow" do
    source = File.read(File.expand_path("../../.github/workflows/_unit_test.yml", __dir__))

    expect(source).not_to include(
      "all-delta",
      "group-full",
      "group-delta",
      "package-cache",
      "minimal-tests",
      "experiment-variant",
    )
  end
end
