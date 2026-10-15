# frozen_string_literal: true

# A data pipeline over the unit test matrix. Four data nouns name the
# stages, and each stage lives in the file of the same name:
#
#   Matrix    the work that exists: one task per suite and Gemfile, read
#             from the Matrixfile (matrix.rb)
#   Timings   what one run measured: setup and test durations per task,
#             written as the timings-*.json artifacts (timings.rb)
#   Weights   what history taught: the learned durations, aggregated from
#             many runs' timings into the manifest (weights.rb)
#   Plan      the decision: which tasks run in which batch, emitted as the
#             workflow matrix JSON (plan.rb)
#
# Runner (runner.rb) executes a plan and produces the next run's Timings.
# The verbs between the nouns: execute (Plan to Timings, runner.rb),
# aggregate (Timings to Weights), and schedule (Matrix plus Weights to
# Plan) in scheduling.rb.
#
# RunTimings and Weights know their own artifact files. Runner is the
# process edge: the only module that runs commands, reads ENV, and
# prints.
module TestBatching
end

require_relative "test_batching/matrix"
require_relative "test_batching/timings"
require_relative "test_batching/weights"
require_relative "test_batching/plan"
require_relative "test_batching/scheduling"
require_relative "test_batching/runner"
