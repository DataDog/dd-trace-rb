# frozen_string_literal: true

# Duration-weighted unit test batching, modeled as the objects it works
# with:
#
#   Task, TaskMatrix            the work: which tasks run under which Ruby
#   TaskTiming, BatchTiming     one batch run's measured durations (T1)
#   Samples, Weights            the learned durations per task and Gemfile
#                               (T2 manifest, T3 costs)
#   Batch, BatchPlan            a scheduled shard and the whole plan
#   Static, Weighted            the two scheduling strategies; rake picks
#                               one based on whether weights exist
#
# TimingFiles and ManifestStore are the filesystem adapters; Runner is the
# process edge. The domain objects never touch File, ENV, or stdout.
module TestBatching
end

require_relative "test_batching/batch"
require_relative "test_batching/batch_plan"
require_relative "test_batching/batch_timing"
require_relative "test_batching/manifest_store"
require_relative "test_batching/runner"
require_relative "test_batching/samples"
require_relative "test_batching/static"
require_relative "test_batching/task"
require_relative "test_batching/task_matrix"
require_relative "test_batching/timing_files"
require_relative "test_batching/weights"
require_relative "test_batching/weighted"
