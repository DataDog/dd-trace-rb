# frozen_string_literal: true

require_relative "batch"
require_relative "batch_plan"

# The default strategy: master's original even-split batching, kept verbatim
# until the weights cache bootstraps. `github:generate_batches` switches to
# Weighted once a weights manifest is available. Delete this class after the
# switch soaks.
module TestBatching
  class Static
    BATCH_COUNT = 7
    private_constant :BATCH_COUNT

    def plan(matrix, ruby_version)
      tasks = matrix.batchable_tasks(ruby_version)

      tasks_per_job = (tasks.size.to_f / BATCH_COUNT).ceil

      batches = tasks.each_slice(tasks_per_job).with_index.map do |task_group, index|
        Batch.new(number: index, tasks: task_group)
      end

      BatchPlan.new(batches: batches, misc_tasks: matrix.misc_tasks(ruby_version))
    end
  end
end
