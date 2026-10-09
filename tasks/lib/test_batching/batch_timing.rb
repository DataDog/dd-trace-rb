# frozen_string_literal: true

require_relative "task"

# One task's measured durations inside a batch run. Absent measurements stay
# nil and are omitted when serialized, so a build-phase file carries only
# build_seconds and a completed run carries all three.
module TestBatching
  class TaskTiming
    attr_reader :task, :build_seconds, :test_seconds, :junit_seconds

    def initialize(task:, build_seconds: nil, test_seconds: nil, junit_seconds: nil)
      @task = task
      @build_seconds = build_seconds
      @test_seconds = test_seconds
      @junit_seconds = junit_seconds
    end

    def matches?(task)
      task.name == @task.name && task.group == @task.group && task.gemfile == @task.gemfile
    end

    def ==(other)
      other.is_a?(TaskTiming) && task == other.task &&
        build_seconds == other.build_seconds && test_seconds == other.test_seconds && junit_seconds == other.junit_seconds
    end
    alias_method :eql?, :==

    def to_h
      task.to_h.merge(
        "build_seconds" => build_seconds,
        "test_seconds" => test_seconds,
        "junit_seconds" => junit_seconds
      ).compact
    end

    def self.from_h(hash)
      new(
        task: Task.from_h(hash),
        build_seconds: hash["build_seconds"],
        test_seconds: hash["test_seconds"],
        junit_seconds: hash["junit_seconds"]
      )
    end
  end

  # The timings-*.json artifact one batch job uploads: its Ruby version and
  # the measured durations of its tasks. The T1 format both TimingFiles and
  # Weights read and write.
  class BatchTiming
    attr_reader :ruby_version, :timings

    def initialize(ruby_version:, timings:)
      @ruby_version = ruby_version
      @timings = timings
    end

    def tasks
      timings.map(&:task)
    end

    def ==(other)
      other.is_a?(BatchTiming) && ruby_version == other.ruby_version && timings == other.timings
    end
    alias_method :eql?, :==

    def find(task)
      timings.find { |timing| timing.matches?(task) }
    end

    # Returns a copy with the timing for that task replaced, or appended when
    # the batch has no prior measurement for it.
    def with_timing(timing)
      index = timings.index { |entry| entry.matches?(timing.task) }
      replaced = timings.dup
      if index
        replaced[index] = timing
      else
        replaced << timing
      end

      self.class.new(ruby_version: ruby_version, timings: replaced)
    end

    def to_h
      {"ruby_version" => ruby_version, "tasks" => timings.map(&:to_h)}
    end

    def self.from_h(hash)
      new(ruby_version: hash.fetch("ruby_version"), timings: hash.fetch("tasks").map { |entry| TaskTiming.from_h(entry) })
    end
  end
end
