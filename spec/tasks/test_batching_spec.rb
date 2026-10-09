# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../../tasks/lib/test_batching"

# Contracts between the timing data formats:
#
#   T1 batch job -> timings-*.json artifacts (BatchTiming / TimingFiles)
#   T2 artifacts -> ci_task_timings.json manifest (Weights.from)
#   T3 manifest -> duration costs and a batch plan (Weights::Ruby, Weighted)
#
# Each boundary must keep parsing when the neighbouring side changes.
RSpec.describe TestBatching do
  it "loads every domain object from the umbrella require" do
    expect(TestBatching.constants.map(&:to_s)).to include(
      "Task", "TaskMatrix", "BatchTiming", "TaskTiming", "Samples", "Weights", "Batch", "BatchPlan",
      "Static", "Weighted", "TimingFiles", "ManifestStore", "Runner"
    )
  end

  before do
    allow(AppraisalConversion).to receive(:parent_gemfile) { "gemfiles/foo.gemfile" }
  end

  it "carries written batch timings through weights into a scheduled plan" do
    ruby = RUBY_VERSION[0..2]

    tasks = [
      TestBatching::Task.new(name: "main", group: "", gemfile: "gemfiles/foo.gemfile"),
      TestBatching::Task.new(name: "profiling", group: "", gemfile: "gemfiles/bar.gemfile"),
    ]
    batch_timing = TestBatching::BatchTiming.new(
      ruby_version: ruby,
      timings: [
        TestBatching::TaskTiming.new(task: tasks.first, build_seconds: 10.0, test_seconds: 30.0),
        TestBatching::TaskTiming.new(task: tasks.last, build_seconds: 20.0, test_seconds: 60.0),
      ]
    )

    Dir.mktmpdir do |directory|
      TestBatching::TimingFiles.write(batch_timing, directory: directory)

      weights = TestBatching::Weights.from(TestBatching::TimingFiles.read_all(directory))
      ruby_weights = weights.for_ruby(ruby)

      expect(ruby_weights.test_cost(tasks.first)).to eq(30.0)
      expect(ruby_weights.setup_cost("foo.gemfile")).to eq(10.0)

      matrix = TestBatching::TaskMatrix.new({"main" => {"" => ["✅ #{ruby}"]}})
      plan = TestBatching::Weighted.new(ruby_weights).plan(matrix, ruby)

      expect(plan.batches.first.tasks.map(&:name)).to eq(["main"])
      expect(plan.batches.first.seconds).to eq(40.0)
    end
  end
end
