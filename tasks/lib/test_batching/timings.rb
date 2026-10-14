# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require_relative "matrix"

# The Timings stage: what one run measured. TaskTiming is one task's
# durations, RunTimings is the whole run's document, and TimingFiles reads
# and writes the per-batch "timings-*.json" artifacts the Unit Tests jobs
# upload.
module TestBatching
  # One task's measured durations inside a run. Absent measurements stay
  # nil and are omitted when serialized, so a build-phase file carries only
  # build_seconds and a completed run carries all three.
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
  class RunTimings
    attr_reader :ruby_version, :timings

    def initialize(ruby_version:, timings:)
      @ruby_version = ruby_version
      @timings = timings
    end

    def tasks
      timings.map(&:task)
    end

    def ==(other)
      other.is_a?(RunTimings) && ruby_version == other.ruby_version && timings == other.timings
    end
    alias_method :eql?, :==

    # Returns a copy with the timing for that task replaced, or appended when
    # the run has no prior measurement for it.
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

  # Filesystem adapter for the Timings stage.
  module TimingFiles
    DEFAULT_DIRECTORY = "tmp/ci-task-timings"

    module_function

    def write(run_timings, directory: DEFAULT_DIRECTORY)
      path = file_path(run_timings.tasks, directory)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.pretty_generate(run_timings.to_h))
    end

    # Reads the timing document for a batch. Returns an empty RunTimings
    # when the batch has never recorded one.
    def read(tasks, directory: DEFAULT_DIRECTORY)
      path = file_path(tasks, directory)
      return RunTimings.new(ruby_version: RUBY_VERSION[0..2], timings: []) unless File.exist?(path)

      RunTimings.from_h(JSON.parse(File.read(path)))
    end

    # Reads every timing document in a directory tree, newest structure
    # first: the downloaded artifact layout of one subdirectory per run.
    def read_all(directory)
      Dir[File.join(directory, "**", "*.json")].map { |path| RunTimings.from_h(JSON.parse(File.read(path))) }
    end

    # Keyed by the current Ruby and the batch task identity so one job's
    # timings never collide with another's across runs.
    def file_path(tasks, directory)
      identity = tasks.flat_map { |task| [task.name, task.group, task.gemfile] }.join("\0")
      digest = Digest::SHA256.hexdigest(identity)[0, 12]
      File.join(directory, "#{RUBY_VERSION[0..2]}-#{digest}.json")
    end

    private_class_method :file_path
  end
end
