# frozen_string_literal: true

require "json"
require "spec_helper"
require "tmpdir"
require_relative "../../../tasks/lib/test_batching/manifest_store"

RSpec.describe TestBatching::ManifestStore do
  it "loads weights from a manifest file" do
    manifest = {"ruby_versions" => {"3.1" => {"tasks" => [], "gemfiles" => []}}}

    Dir.mktmpdir do |directory|
      path = File.join(directory, "manifest.json")
      File.write(path, JSON.pretty_generate(manifest))

      loaded = described_class.load(path: path)

      expect(loaded.to_h).to eq(manifest)
      expect(loaded).to be_a(TestBatching::Weights)
    end
  end

  it "loads missing weights when the file is absent so batching stays static" do
    Dir.mktmpdir do |directory|
      loaded = described_class.load(path: File.join(directory, "missing.json"))

      expect(loaded).to be_a(TestBatching::Weights::Missing)
      expect(loaded).to be_empty
    end
  end

  it "loads missing weights when the file is invalid" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "manifest.json")
      File.write(path, "not json")

      expect(described_class.load(path: path)).to be_a(TestBatching::Weights::Missing)
    end
  end

  it "raises when aggregating a directory without timing files" do
    Dir.mktmpdir do |directory|
      expect { described_class.update_from(directory) }.to raise_error("no timing files found in #{directory}")
    end
  end

  it "aggregates a directory of timing files into the manifest" do
    tasks = [TestBatching::Task.new(name: "main", group: "", gemfile: "gemfiles/foo.gemfile")]
    batch_timing = TestBatching::BatchTiming.new(
      ruby_version: RUBY_VERSION[0..2],
      timings: [TestBatching::TaskTiming.new(task: tasks.first, build_seconds: 10.0, test_seconds: 30.0)]
    )

    Dir.mktmpdir do |directory|
      TestBatching::TimingFiles.write(batch_timing, directory: directory)

      described_class.update_from(directory)

      loaded = described_class.load

      expect(loaded.for_ruby(RUBY_VERSION[0..2]).test_cost(tasks.first)).to eq(30.0)
    ensure
      File.delete(described_class::MANIFEST_PATH) if File.exist?(described_class::MANIFEST_PATH)
    end
  end
end
