# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require_relative "matrix"

# The Timings stage: what one run measured. RunTimings is the run's
# document, and it owns its artifact file: the per-batch
# "timings-*.json" the Unit Tests jobs upload.
module TestBatching
  # One run's timings: its Ruby version and the measured durations of its
  # tasks. The T1 format both Weights and Runner read and write.
  #
  # Each timing entry is a hash in the artifact's own shape: task, group,
  # gemfile, then the measurements the run made so far. Absent
  # measurements are omitted, so a build-phase document carries only
  # build_seconds and a completed run carries all three.
  class RunTimings
    DEFAULT_DIRECTORY = "tmp/ci-task-timings"

    attr_reader :ruby_version, :timings

    def initialize(ruby_version:, timings:)
      @ruby_version = ruby_version
      @timings = timings.map(&:freeze)
    end

    def tasks
      timings.map { |entry| Task.new(name: entry.fetch("task"), group: entry.fetch("group"), gemfile: entry.fetch("gemfile")) }
    end

    def ==(other)
      other.is_a?(RunTimings) && ruby_version == other.ruby_version && timings == other.timings
    end
    alias_method :eql?, :==

    # The one place a timing entry is born: replaces the entry for that
    # task, or appends one when the run has no prior measurement for it.
    def with_timing(task:, build_seconds: nil, test_seconds: nil, junit_seconds: nil)
      entry = task.to_h.merge(
        "build_seconds" => build_seconds,
        "test_seconds" => test_seconds,
        "junit_seconds" => junit_seconds
      ).compact.freeze

      index = timings.index { |existing| entry_matches?(existing, task) }
      replaced = timings.dup
      if index
        replaced[index] = entry
      else
        replaced << entry
      end

      self.class.new(ruby_version: ruby_version, timings: replaced)
    end

    def to_h
      {"ruby_version" => ruby_version, "tasks" => timings.map(&:dup)}
    end

    def self.from_h(hash)
      new(ruby_version: hash.fetch("ruby_version"), timings: hash.fetch("tasks"))
    end

    def self.write(run_timings, directory: DEFAULT_DIRECTORY)
      path = file_path(run_timings.tasks, directory)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.pretty_generate(run_timings.to_h))
    end

    # Reads the timing document for a batch. Returns an empty document
    # when the batch has never recorded one.
    def self.read(tasks, directory: DEFAULT_DIRECTORY)
      path = file_path(tasks, directory)
      return new(ruby_version: RUBY_VERSION[0..2], timings: []) unless File.exist?(path)

      from_h(JSON.parse(File.read(path)))
    end

    # Reads every timing document in a directory tree, newest structure
    # first: the downloaded artifact layout of one subdirectory per run.
    def self.read_all(directory)
      Dir[File.join(directory, "**", "*.json")].map { |path| from_h(JSON.parse(File.read(path))) }
    end

    # Keyed by the current Ruby and the batch task identity so one job's
    # timings never collide with another's across runs.
    def self.file_path(tasks, directory)
      identity = tasks.flat_map { |task| [task.name, task.group, task.gemfile] }.join("\0")
      digest = Digest::SHA256.hexdigest(identity)[0, 12]
      File.join(directory, "#{RUBY_VERSION[0..2]}-#{digest}.json")
    end

    private

    def entry_matches?(entry, task)
      entry.fetch("task") == task.name && entry.fetch("group") == task.group && entry.fetch("gemfile") == task.gemfile
    end

    private_class_method :file_path
  end
end
