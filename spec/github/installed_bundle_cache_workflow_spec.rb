require "spec_helper"
require "open3"
require "tempfile"
require "yaml"

RSpec.describe "installed bundle cache workflow" do
  subject(:ready) { lifecycle_ready(exact_hit: exact_hit, write_enabled: write_enabled) }

  let(:action) do
    YAML.safe_load_file(
      File.expand_path("../../.github/actions/installed-bundle-cache/action.yml", __dir__),
      aliases: true,
    )
  end
  let(:steps) { action.fetch("runs").fetch("steps") }
  let(:lifecycle_step) { steps.find { |step| step["id"] == "lifecycle" } }
  let(:writer_steps) do
    steps.select do |step|
      [
        "Reset installed bundle path",
        "Install complete matrix bundle",
        "Verify complete matrix bundle",
        "Measure installed bundle",
        "Save exact installed bundle",
      ].include?(step["name"])
    end
  end

  def lifecycle_ready(exact_hit:, write_enabled:)
    Tempfile.create do |output|
      environment = {
        "EXACT_HIT" => exact_hit.to_s,
        "WRITE_ENABLED" => write_enabled.to_s,
        "GITHUB_OUTPUT" => output.path,
      }
      _stdout, stderr, status = Open3.capture3(environment, "bash", "-c", lifecycle_step.fetch("run"))
      raise stderr unless status.success?

      File.read(output.path).strip == "ready=true"
    end
  end

  context "with an exact hit" do
    let(:exact_hit) { true }
    let(:write_enabled) { false }

    it { is_expected.to be(true) }

    it "skips writer work" do
      expect(writer_steps).to all(include("if" => "steps.restore.outputs.cache-hit != 'true' && inputs.write-enabled == 'true'"))
    end
  end

  context "with a writable miss" do
    let(:exact_hit) { false }
    let(:write_enabled) { true }

    it { is_expected.to be(true) }

    it "validates before saving" do
      names = steps.map { |step| step["name"] }

      expect(names.index("Verify complete matrix bundle")).to be < names.index("Save exact installed bundle")
    end
  end

  context "with a read-only miss" do
    let(:exact_hit) { false }
    let(:write_enabled) { false }

    it { is_expected.to be(false) }
  end

  context "with an invalid writer generation" do
    let(:exact_hit) { false }
    let(:write_enabled) { true }

    it "does not ignore validation failure" do
      verification = steps.find { |step| step["name"] == "Verify complete matrix bundle" }

      expect(verification).not_to include("continue-on-error")
      expect(verification.fetch("if")).not_to include("always()")
    end
  end
end
