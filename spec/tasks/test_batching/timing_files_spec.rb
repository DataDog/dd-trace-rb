# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../../../tasks/lib/test_batching/timing_files"

RSpec.describe TestBatching::TimingFiles do
  def task(name)
    TestBatching::Task.new(name: name, group: "", gemfile: "gemfiles/#{name}.gemfile")
  end

  def batch_timing(tasks:, build_seconds:, test_seconds: nil)
    TestBatching::BatchTiming.new(
      ruby_version: RUBY_VERSION[0..2],
      timings: tasks.map do |task|
        TestBatching::TaskTiming.new(task: task, build_seconds: build_seconds, test_seconds: test_seconds)
      end
    )
  end

  it "reads back a written batch timing so one job never sees another's file" do
    tasks = [task("main")]
    other = [task("other")]

    Dir.mktmpdir do |directory|
      described_class.write(batch_timing(tasks: tasks, build_seconds: 10.0, test_seconds: 30.0), directory: directory)

      expect(described_class.read(other, directory: directory).timings).to eq([])
      expect(described_class.read(tasks, directory: directory).timings.map(&:test_seconds)).to eq([30.0])
    end
  end

  it "reads every timing document in a directory tree" do
    tasks = [task("main")]

    Dir.mktmpdir do |directory|
      described_class.write(batch_timing(tasks: tasks, build_seconds: 10.0, test_seconds: 30.0), directory: directory)

      expect(described_class.read_all(directory).map(&:ruby_version)).to eq([RUBY_VERSION[0..2]])
    end
  end
end
