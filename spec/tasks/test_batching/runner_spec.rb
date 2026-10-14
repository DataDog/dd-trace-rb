# frozen_string_literal: true

require "spec_helper"
require_relative "../../../tasks/lib/test_batching/runner"

RSpec.describe TestBatching::Runner do
  def task_json(name)
    {"task" => name, "group" => "", "gemfile" => "gemfiles/#{name}.gemfile"}
  end

  before do
    @written = nil
    allow(TestBatching::RunTimings).to receive(:write) { |run_timings| @written = run_timings }
    allow(described_class).to receive(:measure_duration) do |&block|
      block.call
      10.0
    end
    allow(Bundler).to receive(:with_unbundled_env) { |&block| block.call }
    allow(Dir).to receive(:[]).with("tmp/rspec/*.xml").and_return([])
  end

  it "runs each task's install and test and writes the combined run timings" do
    allow(described_class).to receive(:run_command)

    described_class.run([task_json("main"), task_json("contrib")])

    expect(@written.ruby_version).to eq(RUBY_VERSION[0..2])
    expect(@written.timings.map { |entry| entry.fetch("task") }).to eq(["main", "contrib"])
    expect(@written.timings.map { |entry| entry["build_seconds"] }).to eq([10.0, 10.0])
    expect(@written.timings.map { |entry| entry["test_seconds"] }).to eq([10.0, 10.0])
  end

  it "writes the durations completed before a failing task" do
    allow(described_class).to receive(:run_command) do |env, _cmd|
      raise "Command failed" if env.fetch("BUNDLE_GEMFILE").include?("contrib")
    end
    allow(described_class).to receive(:sleep)

    expect { described_class.run([task_json("main"), task_json("contrib")]) }.to raise_error(RuntimeError)

    expect(@written.timings.map { |entry| entry.fetch("task") }).to eq(["main"])
    expect(@written.timings.map { |entry| entry["test_seconds"] }).to eq([10.0])
  end
end
