# frozen_string_literal: true

require "json"
require_relative "batch"

# The plan `github:generate_batches` emits: the batch shards plus the misc
# service tasks, in the matrix JSON shape the Unit Tests workflow consumes.
module TestBatching
  class BatchPlan
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
