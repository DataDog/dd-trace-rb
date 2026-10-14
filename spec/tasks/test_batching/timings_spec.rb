# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../../../tasks/lib/test_batching/timings"

RSpec.describe TestBatching::RunTimings do
  def task(name, group = "")
    TestBatching::Task.new(name: name, group: group, gemfile: "gemfiles/#{name}.gemfile")
  end

  # An entry in the artifact's own shape, the way from_h produces it.
  def entry(task, build_seconds: nil, test_seconds: nil, junit_seconds: nil)
    task.to_h.merge(
      "build_seconds" => build_seconds,
      "test_seconds" => test_seconds,
      "junit_seconds" => junit_seconds
    ).compact
  end

  it "serializes to and from the timings artifact document" do
    run_timings = described_class.new(
      ruby_version: "3.4",
      timings: [entry(task("main"), build_seconds: 10.0, test_seconds: 30.0, junit_seconds: 25.0)]
    )

    expect(described_class.from_h(run_timings.to_h)).to eq(run_timings)
  end

  it "omits measurements the run has not made yet" do
    run_timings = described_class.new(
      ruby_version: "3.4",
      timings: [entry(task("main"), build_seconds: 10.0)]
    )

    expect(run_timings.to_h.fetch("tasks").first.keys).to eq(["task", "group", "gemfile", "build_seconds"])
  end

  it "replaces the timing for a measured task and appends a new one" do
    prior = described_class.new(
      ruby_version: "3.4",
      timings: [entry(task("main"), build_seconds: 10.0), entry(task("contrib"), build_seconds: 5.0)]
    )

    updated = prior.with_timing(task: task("main"), build_seconds: 10.0, test_seconds: 30.0)

    expect(updated.timings.map { |e| e["test_seconds"] }).to eq([30.0, nil])
    expect(updated.timings.map { |e| e.fetch("task") }).to eq(["main", "contrib"])
    expect(prior.timings.map { |e| e["test_seconds"] }).to eq([nil, nil])
  end

  def run_timings(tasks:, build_seconds:, test_seconds: nil)
    described_class.new(
      ruby_version: RUBY_VERSION[0..2],
      timings: tasks.map { |task| entry(task, build_seconds: build_seconds, test_seconds: test_seconds) }
    )
  end

  it "reads back a written timing document so one job never sees another's file" do
    tasks = [task("main")]
    other = [task("other")]

    Dir.mktmpdir do |directory|
      described_class.write(run_timings(tasks: tasks, build_seconds: 10.0, test_seconds: 30.0), directory: directory)

      expect(described_class.read(other, directory: directory).timings).to eq([])
      expect(described_class.read(tasks, directory: directory).timings.map { |e| e["test_seconds"] }).to eq([30.0])
    end
  end

  it "reads every timing document in a directory tree" do
    tasks = [task("main")]

    Dir.mktmpdir do |directory|
      described_class.write(run_timings(tasks: tasks, build_seconds: 10.0, test_seconds: 30.0), directory: directory)

      expect(described_class.read_all(directory).map(&:ruby_version)).to eq([RUBY_VERSION[0..2]])
    end
  end
end
