# frozen_string_literal: true

require "json"

# The Plan stage: the decision. Batch is one shard, Plan is the whole
# schedule in the workflow matrix JSON shape the Unit Tests workflow
# consumes. The strategies in scheduling.rb compute it.
module TestBatching
  # One shard of the plan: its tasks and, when the plan is weighted, its
  # estimated total seconds.
  Batch = Struct.new(:number, :tasks, :seconds, keyword_init: true)

  # The plan `github:schedule_batches` emits: the batch shards plus the misc
  # service tasks, in the matrix JSON shape the Unit Tests workflow consumes.
  class Plan
    attr_reader :batches, :misc_tasks

    def initialize(batches:, misc_tasks:)
      @batches = batches
      @misc_tasks = misc_tasks
    end

    def to_matrix
      {
        "batches" => {"include" => batches.map { |batch| batch_entry(batch) }},
        "misc" => {"include" => [{"batch" => "0", "tasks" => misc_tasks.map(&:to_h)}]},
      }
    end

    def to_json
      JSON.dump(to_matrix)
    end

    private

    def batch_entry(batch)
      entry = {"batch" => batch.number.to_s, "tasks" => batch.tasks.map(&:to_h)}
      entry["estimated_seconds"] = batch.seconds.round(1) if batch.seconds
      entry
    end
  end
end
