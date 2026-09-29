require "spec_helper"
require "open3"
require "tempfile"
require "yaml"

RSpec.describe "installed bundle cache workflow" do
  subject(:lifecycle) do
    lifecycle_result(exact_hit: exact_hit, matched_key: matched_key, write_enabled: write_enabled)
  end

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
  let(:group_action) do
    YAML.safe_load_file(
      File.expand_path("../../.github/actions/installed-bundle-group-cache/action.yml", __dir__),
      aliases: true,
    )
  end
  let(:steps) { action.fetch("runs").fetch("steps") }
  let(:workflow) do
    YAML.safe_load_file(
      File.expand_path("../../.github/workflows/_unit_test.yml", __dir__),
      aliases: true,
    )
  end
  let(:lifecycle_step) { steps.find { |step| step["id"] == "lifecycle" } }
  let(:result_step) { steps.find { |step| step["id"] == "result" } }

  def run_output(script, environment)
    Tempfile.create do |output|
      env = environment.merge("GITHUB_OUTPUT" => output.path)
      _stdout, stderr, status = Open3.capture3(env, "bash", "-c", script)
      raise stderr unless status.success?

      File.readlines(output.path, chomp: true).to_h { |line| line.split("=", 2) }
    end
  end

  def lifecycle_result(exact_hit:, matched_key:, write_enabled:)
    lifecycle_output = run_output(
      lifecycle_step.fetch("run"),
      {
        "EXACT_HIT" => exact_hit.to_s,
        "MATCHED_KEY" => matched_key,
        "WRITE_ENABLED" => write_enabled.to_s,
      },
    )
    result_output = run_output(
      result_step.fetch("run"),
      {
        "INITIAL_STATUS" => lifecycle_output.fetch("status"),
        "WRITE_ENABLED" => write_enabled.to_s,
      },
    )

    lifecycle_output.merge(result_output)
  end

  def group_lifecycle(overrides = {})
    group_steps = group_action.fetch("runs").fetch("steps")
    lifecycle = group_steps.find { |step| step["id"] == "lifecycle" }
    environment = %w[STANDARD_0 STANDARD_1 STANDARD_2 STANDARD_3 STANDARD_4 STANDARD_5 STANDARD_6 MISC_0].each_with_object({}) do |name, values|
      values["#{name}_HIT"] = "true"
      values["#{name}_MATCH"] = "current-key"
    end

    run_output(lifecycle.fetch("run"), environment.merge(overrides))
  end

  context "with an exact hit" do
    let(:exact_hit) { true }
    let(:matched_key) { "current-key" }
    let(:write_enabled) { false }

    it { is_expected.to include("status" => "exact", "ready" => "true", "repair" => "false") }
  end

  context "with a writable miss" do
    let(:exact_hit) { false }
    let(:matched_key) { "" }
    let(:write_enabled) { true }

    it { is_expected.to include("status" => "generated", "ready" => "true", "repair" => "true") }

    it "validates before saving" do
      names = steps.map { |step| step["name"] }

      expect(names.index("Verify complete matrix bundle")).to be < names.index("Save installed bundle")
    end
  end

  context "with a read-only partial restore" do
    let(:exact_hit) { false }
    let(:matched_key) { "older-key" }
    let(:write_enabled) { false }

    it { is_expected.to include("status" => "partial", "ready" => "false", "repair" => "true") }
  end

  context "with a read-only miss" do
    let(:exact_hit) { false }
    let(:matched_key) { "" }
    let(:write_enabled) { false }

    it { is_expected.to include("status" => "miss", "ready" => "false", "repair" => "false") }
  end

  it "restores deltas only through the environment-specific prefix" do
    restore = steps.find { |step| step["id"] == "restore" }

    expect(restore.fetch("with").fetch("restore-keys")).to include("steps.manifest.outputs.restore-prefix")
    expect(restore.fetch("with").fetch("restore-keys")).not_to include("cache-schema")
  end

  it "applies restored deltas over the installed base" do
    apply = steps.find { |step| step["name"] == "Apply installed bundle delta" }

    expect(apply.fetch("if")).to include("inputs.strategy == 'all-delta'")
    expect(apply.fetch("run")).to include("cp -a /tmp/ddtrace-installed-bundle-delta/. /usr/local/bundle/")
  end

  it "makes child delta restores use the same environment-specific prefix" do
    restore = restore_action.fetch("runs").fetch("steps").find { |step| step["id"] == "restore" }

    expect(restore.fetch("with").fetch("restore-keys")).to include("inputs.restore-prefix")
  end

  context "with an installed-cache strategy selector" do
    it "defaults reusable workflow calls to disabled" do
      inputs = workflow.fetch(true).fetch("workflow_call").fetch("inputs")

      expect(inputs.fetch("installed-cache-strategy").fetch("default")).to eq("disabled")
    end

    it "offers every installed-cache experiment for direct dispatch" do
      inputs = workflow.fetch(true).fetch("workflow_dispatch").fetch("inputs")

      expect(inputs.fetch("installed-cache-strategy").fetch("options")).to eq(
        %w[disabled full all-delta group-full group-delta]
      )
    end

    it "passes the experimental content-key variant to the cache action" do
      batch_steps = workflow.fetch("jobs").fetch("batch").fetch("steps")
      installed = batch_steps.find { |step| step["name"] == "Prepare installed matrix bundle cache" }

      expect(installed.fetch("with").fetch("experiment-variant")).to include(
        "inputs.installed-cache-key-variant"
      )
    end

    it "prepares the base cache before an all-delta installed cache" do
      batch_steps = workflow.fetch("jobs").fetch("batch").fetch("steps")
      names = batch_steps.map { |step| step["name"] }
      base = batch_steps.find { |step| step["name"] == "Prepare bundle cache" }
      installed = batch_steps.find { |step| step["name"] == "Prepare installed matrix bundle cache" }

      expect(names.index("Prepare bundle cache")).to be < names.index("Prepare installed matrix bundle cache")
      expect(base.fetch("if")).to include("!= 'full'")
      expect(installed.fetch("with").fetch("base-cache-key")).to include("steps.bundle-cache.outputs.cache-key")
      expect(installed.fetch("with").fetch("cache-schema")).to include("bundle-installed-matrix-s2-v1-all-delta")
    end

    it "prepares group caches after distributing tasks" do
      batch_steps = workflow.fetch("jobs").fetch("batch").fetch("steps")
      names = batch_steps.map { |step| step["name"] }
      grouped = batch_steps.find { |step| step["name"] == "Prepare installed bundle group caches" }

      expect(names.index("Distribute tasks into batches")).to be < names.index("Prepare installed bundle group caches")
      expect(grouped.fetch("with")).to include(
        "standard-groups" => include("steps.set-batches.outputs.batches"),
        "misc-groups" => include("steps.set-batches.outputs.misc"),
      )
    end

    it "restores and saves all eight group entries" do
      group_steps = group_action.fetch("runs").fetch("steps")
      restores = group_steps.select { |step| step.fetch("id", "").start_with?("restore-standard-", "restore-misc-") }
      saves = group_steps.select { |step| step.fetch("name", "").start_with?("Save standard-", "Save misc-") }

      expect(restores.size).to eq(8)
      expect(saves.size).to eq(8)
      expect(restores).to all(include("with" => include("restore-keys" => include("prefix"))))
    end

    it "classifies all exact group restores as exact" do
      expect(group_lifecycle).to include(
        "status" => "exact",
        "exact-hit" => "true",
        "standard-0-status" => "exact",
      )
    end

    it "classifies an older group restore as partial" do
      result = group_lifecycle("STANDARD_3_HIT" => "false", "STANDARD_3_MATCH" => "older-key")

      expect(result).to include(
        "status" => "partial",
        "exact-hit" => "false",
        "standard-3-status" => "partial",
      )
    end

    it "classifies any absent group as a miss" do
      result = group_lifecycle("MISC_0_HIT" => "false", "MISC_0_MATCH" => "")

      expect(result).to include("status" => "miss", "misc-0-status" => "miss")
    end

    it "selects each child cache by job kind and batch" do
      jobs = workflow.fetch("jobs")

      %w[build-test-standard build-test-misc].each do |job_name|
        restore = jobs.fetch(job_name).fetch("steps").find do |step|
          step["name"] == "Restore installed matrix bundle"
        end

        expect(restore.fetch("with").fetch("cache-key")).to include(
          "env.INSTALLED_CACHE_GROUP_KIND",
          "matrix.batch",
        )
      end
    end

    it "keeps downloaded-package work out of installed-cache runs" do
      batch_steps = workflow.fetch("jobs").fetch("batch").fetch("steps")
      package_steps = batch_steps.select { |step| step.fetch("name", "").include?("package cache") }

      expect(package_steps).to all(include("if" => include("inputs.installed-cache-strategy == 'disabled'")))
    end
  end
end
