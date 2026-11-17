# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../../tasks/lib/test_batching"

# Contracts between the pipeline's data formats:
#
#   T1 batch job -> timings-*.json artifacts (RunTimings writes its own file)
#   T2 artifacts -> ci_task_timings.json manifest (Weights.aggregate)
#   T3 manifest -> duration costs and a batch plan (Weights#for_ruby, Weighted)
#
# Each boundary must keep parsing when the neighbouring side changes.
RSpec.describe TestBatching do
  it "loads every pipeline object from the umbrella require" do
    expect(TestBatching.constants.map(&:to_s)).to include(
      "Task", "TaskMatrix", "RunTimings", "Weights", "Batch", "Plan",
      "Static", "Weighted", "Runner",
    )
  end

  before do
    allow(AppraisalConversion).to receive(:parent_gemfile) { "gemfiles/foo.gemfile" }
  end

  it "carries written run timings through weights into a scheduled plan" do
    ruby = RUBY_VERSION[0..2]

    tasks = [
      TestBatching::Task.new(name: "main", group: "", gemfile: "gemfiles/foo.gemfile"),
      TestBatching::Task.new(name: "profiling", group: "", gemfile: "gemfiles/bar.gemfile"),
    ]
    run_timings = TestBatching::RunTimings.new(ruby_version: ruby, timings: [])
    run_timings = run_timings.with_timing(task: tasks.first, build_seconds: 10.0, test_seconds: 30.0)
    run_timings = run_timings.with_timing(task: tasks.last, build_seconds: 20.0, test_seconds: 60.0)

    Dir.mktmpdir do |directory|
      run_timings.write(directory: directory)

      weights = TestBatching::Weights.from(TestBatching::RunTimings.read_all(directory))
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
