# frozen_string_literal: true

require "json"
require "spec_helper"
require "tmpdir"
require_relative "../../../tasks/lib/test_batching/weights"

RSpec.describe TestBatching::Weights do
  def task(name, gemfile: "gemfiles/foo.gemfile")
    TestBatching::Task.new(name: name, group: "", gemfile: gemfile)
  end

  it "separates task execution from Gemfile setup and reports p50 and p90" do
    # Three runs of one batch: main and contrib share the parent Gemfile.
    runs = [[10, 4], [30, 8], [20, 6]].map do |main_test, main_build|
      TestBatching::RunTimings.new(
        ruby_version: "3.1",
        timings: [
          {"task" => "main", "group" => "", "gemfile" => "gemfiles/foo.gemfile", "build_seconds" => main_build, "test_seconds" => main_test},
          {"task" => "contrib", "group" => "", "gemfile" => "gemfiles/foo.gemfile", "build_seconds" => 1, "test_seconds" => 5},
        ]
      )
    end

    weights = described_class.from(runs)

    expect(weights.to_h).to eq({
      "ruby_versions" => {
        "3.1" => {
          "tasks" => [
            {"p50_seconds" => 5, "p90_seconds" => 5, "samples" => 3, "task" => "contrib", "group" => ""},
            {"p50_seconds" => 20, "p90_seconds" => 30, "samples" => 3, "task" => "main", "group" => ""},
          ],
          "gemfiles" => [
            {"p50_seconds" => 7, "p90_seconds" => 9, "samples" => 3, "gemfile" => "foo.gemfile"},
          ],
        },
      },
    })
  end

  it "averages the middle pair for an even sample count and rounds to milliseconds" do
    runs = [10.12345, 20.0, 30.5, 40.0].map do |test_seconds|
      TestBatching::RunTimings.new(
        ruby_version: "3.1",
        timings: [{"task" => "main", "group" => "", "gemfile" => "gemfiles/foo.gemfile", "build_seconds" => 1, "test_seconds" => test_seconds}]
      )
    end

    entry = described_class.from(runs).to_h.fetch("ruby_versions").fetch("3.1").fetch("tasks").first

    expect(entry).to include("p50_seconds" => 25.25, "p90_seconds" => 40.0, "samples" => 4)
  end

  it "answers costs per Ruby, falling back for tasks without history" do
    weights = described_class.new({
      "ruby_versions" => {
        "3.1" => {
          "tasks" => [{"task" => "main", "group" => "", "p90_seconds" => 42}],
          "gemfiles" => [{"gemfile" => "Gemfile", "p90_seconds" => 5}],
        },
      },
    })

    ruby = weights.for_ruby("3.1")
    expect(ruby.test_cost(task("main"))).to eq(42)
    expect(ruby.setup_cost("Gemfile")).to eq(5)

    # A task and Gemfile without history fall back to the upper quartile.
    expect(ruby.test_cost(task("unknown"))).to eq(42)
    expect(ruby.setup_cost("unknown.gemfile")).to eq(5)
  end

  it "falls back to a minute for a Ruby it has never seen" do
    weights = described_class.new({
      "ruby_versions" => {
        "3.1" => {
          "tasks" => [{"task" => "main", "group" => "", "p90_seconds" => 42}],
          "gemfiles" => [{"gemfile" => "Gemfile", "p90_seconds" => 5}],
        },
      },
    })

    other_ruby = weights.for_ruby("3.2")

    expect(other_ruby.test_cost(task("main"))).to eq(60.0)
    expect(other_ruby.setup_cost("Gemfile")).to eq(60.0)
  end

  it "knows when it carries no weights at all" do
    expect(described_class.new({}).empty?).to be(true)
  end

  it "loads weights from a manifest file" do
    manifest = {"ruby_versions" => {"3.1" => {"tasks" => [], "gemfiles" => []}}}

    Dir.mktmpdir do |directory|
      path = File.join(directory, "manifest.json")
      File.write(path, JSON.pretty_generate(manifest))

      loaded = described_class.load(path: path)

      expect(loaded.to_h).to eq(manifest)
      expect(loaded).to be_a(described_class)
    end
  end

  it "loads empty weights when the file is absent so batching stays static" do
    Dir.mktmpdir do |directory|
      loaded = described_class.load(path: File.join(directory, "missing.json"))

      expect(loaded).to be_a(described_class)
      expect(loaded).to be_empty
    end
  end

  it "loads empty weights when the file is invalid" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "manifest.json")
      File.write(path, "not json")

      expect(described_class.load(path: path)).to be_empty
    end
  end

  it "raises when aggregating a directory without timing files" do
    Dir.mktmpdir do |directory|
      expect { described_class.aggregate(directory) }.to raise_error("no timing files found in #{directory}")
    end
  end

  it "aggregates a directory of timing files into the manifest" do
    run_timings = TestBatching::RunTimings.new(
      ruby_version: RUBY_VERSION[0..2],
      timings: [{"task" => "main", "group" => "", "gemfile" => "gemfiles/foo.gemfile", "build_seconds" => 10.0, "test_seconds" => 30.0}]
    )

    Dir.mktmpdir do |directory|
      TestBatching::RunTimings.write(run_timings, directory: directory)

      described_class.aggregate(directory)

      main = TestBatching::Task.new(name: "main", group: "", gemfile: "gemfiles/foo.gemfile")
      loaded = described_class.load

      expect(loaded.for_ruby(RUBY_VERSION[0..2]).test_cost(main)).to eq(30.0)
    ensure
      File.delete(described_class::MANIFEST_PATH) if File.exist?(described_class::MANIFEST_PATH)
    end
  end
end
