# frozen_string_literal: true

require "spec_helper"
require_relative "../../../tasks/lib/test_batching/batch_timing"

RSpec.describe TestBatching::BatchTiming do
  def task(name, group = "")
    TestBatching::Task.new(name: name, group: group, gemfile: "gemfiles/#{name}.gemfile")
  end

  def timing(task, build_seconds: nil, test_seconds: nil, junit_seconds: nil)
    TestBatching::TaskTiming.new(
      task: task, build_seconds: build_seconds, test_seconds: test_seconds, junit_seconds: junit_seconds
    )
  end

  it "serializes to and from the timings artifact document" do
    batch_timing = described_class.new(
      ruby_version: "3.4",
      timings: [timing(task("main"), build_seconds: 10.0, test_seconds: 30.0, junit_seconds: 25.0)]
    )

    expect(described_class.from_h(batch_timing.to_h)).to eq(batch_timing)
  end

  it "omits measurements the run has not made yet" do
    batch_timing = described_class.new(
      ruby_version: "3.4",
      timings: [timing(task("main"), build_seconds: 10.0)]
    )

    expect(batch_timing.to_h.fetch("tasks").first.keys).to eq(["task", "group", "gemfile", "build_seconds"])
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
