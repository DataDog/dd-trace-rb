# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require_relative "batch_timing"

# Filesystem adapter: reads and writes the per-batch timing documents that
# the Unit Tests jobs upload as "timings-*.json" artifacts.
module TestBatching
  module TimingFiles
    DEFAULT_DIRECTORY = "tmp/ci-task-timings"

    module_function

    def write(batch_timing, directory: DEFAULT_DIRECTORY)
      path = file_path(batch_timing.tasks, directory)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.pretty_generate(batch_timing.to_h))
    end

    # Reads the timing document for a batch. Returns an empty BatchTiming
    # when the batch has never recorded one.
    def read(tasks, directory: DEFAULT_DIRECTORY)
      path = file_path(tasks, directory)
      return BatchTiming.new(ruby_version: RUBY_VERSION[0..2], timings: []) unless File.exist?(path)

      BatchTiming.from_h(JSON.parse(File.read(path)))
    end

    # Reads every timing document in a directory tree, newest structure
    # first: the downloaded artifact layout of one subdirectory per run.
    def read_all(directory)
      Dir[File.join(directory, "**", "*.json")].map { |path| BatchTiming.from_h(JSON.parse(File.read(path))) }
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
