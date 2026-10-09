# frozen_string_literal: true

# One shard of the batch plan: its tasks and, when the plan is weighted, its
# estimated total seconds.
module TestBatching
  class Batch
    attr_reader :number, :tasks, :seconds

    def initialize(number:, tasks:, seconds: nil)
      @number = number
      @tasks = tasks
      @seconds = seconds
    end
  end
end
