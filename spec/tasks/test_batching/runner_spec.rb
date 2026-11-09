# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../../../tasks/lib/test_batching/runner"

RSpec.describe TestBatching::Runner do
  def task_json(name)
    {"task" => name, "group" => "", "gemfile" => "gemfiles/#{name}.gemfile"}
  end

  around do |example|
    Dir.mktmpdir { |directory| Dir.chdir(directory) { example.run } }
  end

  before do
    allow(described_class).to receive(:measure_duration) do |&block|
      block.call
      10.0
    end
    allow(Bundler).to receive(:with_unbundled_env) { |&block| block.call }
    allow(Dir).to receive(:[]).and_call_original
    allow(Dir).to receive(:[]).with("tmp/rspec/*.xml").and_return([])
  end

  def written_run
    TestBatching::RunTimings.read_all("tmp/ci-task-timings").first
  end

  it "runs each task's install and test and writes the combined run timings" do
    allow(described_class).to receive(:run_command)

    described_class.run([task_json("main"), task_json("contrib")])

    expect(written_run.ruby_version).to eq(RUBY_VERSION[0..2])
    expect(written_run.timings.map { |entry| entry.fetch("task") }).to eq(["main", "contrib"])
    expect(written_run.timings.map { |entry| entry["build_seconds"] }).to eq([10.0, 10.0])
    expect(written_run.timings.map { |entry| entry["test_seconds"] }).to eq([10.0, 10.0])
  end

  it "quiets bundle install by default" do
    cmds = []
    allow(described_class).to receive(:run_command) { |_env, cmd| cmds << cmd }
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("RUNNER_DEBUG").and_return(nil)

    described_class.run([task_json("main")])

    expect(cmds.first).to include("bundle install --quiet")
  end

  it "shows full bundle install output when the job runs with debug logging" do
    cmds = []
    allow(described_class).to receive(:run_command) { |_env, cmd| cmds << cmd }
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("RUNNER_DEBUG").and_return("1")

    described_class.run([task_json("main")])

    expect(cmds.first).not_to include("--quiet")
  end

  it "writes the durations completed before a failing task" do
    allow(described_class).to receive(:run_command) do |env, _cmd|
      raise "Command failed" if env.fetch("BUNDLE_GEMFILE").include?("contrib")
    end
    allow(described_class).to receive(:sleep)

    expect { described_class.run([task_json("main"), task_json("contrib")]) }.to raise_error(RuntimeError)

    expect(written_run.timings.map { |entry| entry.fetch("task") }).to eq(["main"])
    expect(written_run.timings.map { |entry| entry["test_seconds"] }).to eq([10.0])
  end
end
