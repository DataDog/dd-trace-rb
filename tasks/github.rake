# frozen_string_literal: true

require "json"
require_relative "lib/test_batching"

# Each task is one step of the Unit Tests / Update Task Weights workflows,
# which own the pipeline's orchestration.

namespace :github do
  desc "Emit the batched task matrix as JSON (Unit Tests batch job)"
  task :generate_batches do
    matrix = TestBatching::TaskMatrix.new(eval(File.read("Matrixfile")).freeze) # rubocop:disable Security/Eval
    ruby_version = RUBY_VERSION[0..2]

    # Weighted batching turns itself on once the scheduled Update Task Weights
    # workflow has saved a manifest into the cache. Until then keep master's
    # static even-split batching, byte-identical to today.
    weights = TestBatching::ManifestStore.load
    strategy =
      if weights.empty?
        TestBatching::Static.new
      else
        TestBatching::Weighted.new(weights.for_ruby(ruby_version))
      end

    puts strategy.plan(matrix, ruby_version).to_json
  end

  desc "Append the batch matrix to the job's step summary"
  task :generate_batch_summary do
    TestBatching::Runner.write_batch_summary(ENV["batches_json"])
  end

  desc "Aggregate a directory of downloaded timing artifacts into the weights manifest"
  task :update_task_timings, [:directory] do |_, args|
    directory = args[:directory]
    raise "timings directory not provided" if directory.to_s.empty?

    TestBatching::ManifestStore.update_from(directory)
  end

  desc "Run the build steps of one batch and record the Gemfile setup durations"
  task :run_batch_build do
    TestBatching::Runner.build(JSON.parse(ENV["BATCHED_TASKS"] || {}))
  end

  desc "Run the test steps of one batch and record the task durations"
  task :run_batch_tests do
    TestBatching::Runner.tests(JSON.parse(ENV["BATCHED_TASKS"] || {}))
  end
end
