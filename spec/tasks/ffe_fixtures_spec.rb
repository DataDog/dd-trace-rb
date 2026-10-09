# frozen_string_literal: true

require "spec_helper"
require_relative "../../tasks/ffe_fixtures"

RSpec.describe FfeFixtures do
  around do |example|
    Dir.mktmpdir("ffe-fixtures-spec-") do |temporary|
      @temporary = temporary
      example.run
    end
  end

  let(:repository) { File.join(@temporary, "repository") }
  let(:upstream) { File.join(@temporary, "upstream") }
  let(:destination) { File.join(repository, described_class::DESTINATION) }
  let(:commit) { "a" * 40 }
  let(:output_file) { File.join(@temporary, "github-output") }

  before do
    [upstream, destination].each do |directory|
      FileUtils.mkdir_p(File.join(directory, "evaluation-cases"))
      File.write(File.join(directory, "ufc-config.json"), '{"flags":{}}')
      File.write(File.join(directory, "evaluation-cases", "cases.json"), '[{"flag":"test"}]')
    end
    File.write(File.join(destination, "SOURCE.md"), described_class.source_metadata(commit))
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:[]).with("GITHUB_OUTPUT").and_return(output_file)
    allow(ENV).to receive(:fetch).with("GITHUB_OUTPUT").and_return(output_file)
    allow(described_class).to receive(:git) do |directory, _environment, *arguments|
      case arguments.first
      when "checkout"
        FileUtils.cp_r(Dir[File.join(upstream, "*")], directory, dereference_root: false)
        ""
      when "rev-parse" then commit
      else ""
      end
    end
  end

  def snapshot_state
    described_class.files(destination).map do |name|
      path = File.join(destination, name)
      [name, File.binread(path), File.mtime(path)]
    end
  end

  describe ".validate_ref" do
    ["main", "feature/fixtures", "v1.2.3", "a" * 40].each do |ref|
      it "accepts #{ref}" do
        expect { described_class.validate_ref(ref) }.not_to raise_error
      end
    end

    ["", " ", "--upload-pack=evil", "main..other", "main;echo"].each do |ref|
      it "rejects #{ref.inspect} before fetching" do
        expect(described_class).not_to receive(:git)
        expect { described_class.update(repository, ref: ref) }.to raise_error(ArgumentError, /Invalid FFE fixture ref/)
      end
    end
  end

  describe ".update" do
    it "checks the recorded commit without changing files or writing outputs" do
      before = snapshot_state
      expect(described_class).to receive(:git).with(anything, anything, "fetch", "--quiet", "--depth", "1", "origin", commit)

      described_class.update(repository, check: true)

      expect(snapshot_state).to eq(before)
      expect(File.exist?(output_file)).to be(false)
    end

    ["modified", "missing", "extra"].each do |change|
      it "rejects #{change} fixture contents without repairing them in check mode" do
        case_file = File.join(destination, "evaluation-cases", "cases.json")
        case change
        when "modified" then File.write(case_file, "[]")
        when "missing" then File.delete(case_file)
        when "extra" then File.write(File.join(destination, "extra.json"), "{}")
        end
        before = snapshot_state

        expect { described_class.update(repository, check: true) }.to raise_error(/does not match SOURCE.md/)
        expect(snapshot_state).to eq(before)
      end
    end

    ["main", "a" * 7, "g" * 40, "a" * 40 + "\nSource commit: " + "b" * 40].each do |source_commit|
      it "rejects invalid source metadata #{source_commit.inspect} before fetching" do
        File.write(File.join(destination, "SOURCE.md"), "Source commit: #{source_commit}\n")
        expect(described_class).not_to receive(:git)

        expect { described_class.update(repository, check: true) }.to raise_error(/exactly one full upstream commit SHA/)
      end
    end

    it "rejects a fetched commit that differs from the recorded SHA" do
      File.write(File.join(destination, "SOURCE.md"), described_class.source_metadata("b" * 40))

      expect { described_class.update(repository, check: true) }.to raise_error(/does not match recorded SHA/)
    end

    it "updates changed contents, excludes unrelated upstream files, and preserves a subsequent no-op snapshot" do
      File.write(File.join(upstream, "ufc-config.json"), '{"flags":{"new":{}}}')
      File.write(File.join(upstream, "README.md"), "upstream documentation")

      described_class.update(repository)

      expect(File.read(File.join(destination, "ufc-config.json"))).to eq('{"flags":{"new":{}}}')
      expect(File.exist?(File.join(destination, "README.md"))).to be(false)
      expect(described_class.recorded_commit(destination)).to eq(commit)
      expect(File.read(output_file)).to include("changed=true\n", "fixture_count=1\n")
      before = snapshot_state
      described_class.update(repository)
      expect(snapshot_state).to eq(before)
      expect(File.read(output_file)).to end_with("changed=false\n")
    end

    ["ufc-config.json", "evaluation-cases", "evaluation-cases/cases.json"].each do |entry|
      it "rejects upstream symlinks at #{entry} without changing the snapshot" do
        path = File.join(upstream, entry)
        target = File.join(@temporary, "target")
        FileUtils.mv(path, target)
        File.symlink(target, path)
        before = snapshot_state

        expect { described_class.update(repository) }.to raise_error(/Unsupported FFE/)
        expect(snapshot_state).to eq(before)
      end
    end

    ["README.md", "nested.json"].each do |entry|
      it "rejects unexpected case entry #{entry}" do
        path = File.join(upstream, "evaluation-cases", entry)
        (entry == "nested.json") ? Dir.mkdir(path) : File.write(path, "unexpected")

        expect { described_class.update(repository) }.to raise_error(/Unexpected FFE|Unsupported FFE/)
      end
    end

    ["[]", "{}", "invalid JSON"].each do |contents|
      it "rejects unusable case contents #{contents.inspect} without changing the snapshot" do
        File.write(File.join(upstream, "evaluation-cases", "cases.json"), contents)
        before = snapshot_state

        expect { described_class.update(repository) }.to raise_error(StandardError)
        expect(snapshot_state).to eq(before)
      end
    end
  end

  describe ".main" do
    it "rejects an override of the recorded commit in check mode" do
      expect(described_class).not_to receive(:update)

      expect { described_class.main(["--check", "--ref", "main"]) }.to raise_error(OptionParser::InvalidOption)
    end

    [[], ["--ref", "reviewed-ref"], ["--check"]].each do |arguments|
      it "selects the mode for #{arguments.inspect}" do
        expect(described_class).to receive(:update).with(
          File.expand_path("../..", __dir__),
          ref: arguments.include?("--ref") ? "reviewed-ref" : "main",
          check: arguments.include?("--check"),
        )

        described_class.main(arguments.dup)
      end
    end
  end
end
