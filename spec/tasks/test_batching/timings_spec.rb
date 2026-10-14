# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../../../tasks/lib/test_batching/timings"

RSpec.describe TestBatching::RunTimings do
  def task(name, group = "")
    TestBatching::Task.new(name: name, group: group, gemfile: "gemfiles/#{name}.gemfile")
  end

  def timing(task, build_seconds: nil, test_seconds: nil, junit_seconds: nil)
    TestBatching::TaskTiming.new(
      task: task, build_seconds: build_seconds, test_seconds: test_seconds, junit_seconds: junit_seconds
    )
  end

  it "serializes to and from the timings artifact document" do
    run_timings = described_class.new(
      ruby_version: "3.4",
      timings: [timing(task("main"), build_seconds: 10.0, test_seconds: 30.0, junit_seconds: 25.0)]
    )

    expect(described_class.from_h(run_timings.to_h)).to eq(run_timings)
  end

  it "omits measurements the run has not made yet" do
    run_timings = described_class.new(
      ruby_version: "3.4",
      timings: [timing(task("main"), build_seconds: 10.0)]
    )

    expect(run_timings.to_h.fetch("tasks").first.keys).to eq(["task", "group", "gemfile", "build_seconds"])
  end

  it "replaces the timing for a measured task and appends a new one" do
    prior = described_class.new(
      ruby_version: "3.4",
      timings: [timing(task("main"), build_seconds: 10.0), timing(task("contrib"), build_seconds: 5.0)]
    )

    updated = prior.with_timing(timing(task("main"), build_seconds: 10.0, test_seconds: 30.0))

    expect(updated.timings.map(&:test_seconds)).to eq([30.0, nil])
    expect(updated.timings.map { |entry| entry.task.name }).to eq(["main", "contrib"])
    expect(prior.timings.map(&:test_seconds)).to eq([nil, nil])
  end
end

RSpec.describe TestBatching::TimingFiles do
  def task(name)
    TestBatching::Task.new(name: name, group: "", gemfile: "gemfiles/#{name}.gemfile")
  end

  def run_timings(tasks:, build_seconds:, test_seconds: nil)
    TestBatching::RunTimings.new(
      ruby_version: RUBY_VERSION[0..2],
      timings: tasks.map do |task|
        TestBatching::TaskTiming.new(task: task, build_seconds: build_seconds, test_seconds: test_seconds)
      end
    )
  end

  it "reads back a written timing document so one job never sees another's file" do
    tasks = [task("main")]
    other = [task("other")]

    Dir.mktmpdir do |directory|
      described_class.write(run_timings(tasks: tasks, build_seconds: 10.0, test_seconds: 30.0), directory: directory)

      expect(described_class.read(other, directory: directory).timings).to eq([])
      expect(described_class.read(tasks, directory: directory).timings.map(&:test_seconds)).to eq([30.0])
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
