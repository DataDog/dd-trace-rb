# frozen_string_literal: true

require "json"
require_relative "timings"

# The Weights stage: what history taught. Samples computes the percentiles,
# Weights answers cost queries per Ruby, and ManifestStore is the filesystem
# adapter for the aggregated manifest the scheduled workflow publishes and
# the batch job consumes.
module TestBatching
  # An observed set of durations for one task or Gemfile. Knows its own
  # percentiles, which become the weight entries in the manifest.
  class Samples
    def initialize(values)
      @sorted = values.sort
    end

    def to_h
      {"p50_seconds" => p50.round(3), "p90_seconds" => p90.round(3), "samples" => size}
    end

    private

    def size
      @sorted.length
    end

    def p50
      middle = size / 2
      return @sorted[middle] if size.odd?

      (@sorted[middle - 1] + @sorted[middle]) / 2.0
    end

    def p90
      @sorted.fetch(((size - 1) * 0.9).ceil)
    end
  end

  # The aggregated weights: what CI knows about how long tasks and Gemfiles
  # take, per Ruby. Built from runs' timings. Answers cost queries.
  class Weights
    def initialize(manifest)
      @manifest = manifest
    end

    def self.from(runs)
      task_samples = {}
      gemfile_samples = {}

      runs.each do |run_timings|
        ruby_version = run_timings.ruby_version

        run_timings.timings.each do |timing|
          unless timing.test_seconds
            raise KeyError, "timing without test_seconds: #{timing.task.name} (#{timing.task.group})"
          end

          key = [ruby_version, timing.task.name, timing.task.group]
          (task_samples[key] ||= []) << timing.test_seconds
        end

        run_timings.timings.group_by { |timing| timing.task.gemfile_name }.each do |gemfile, timings|
          timings.each do |timing|
            unless timing.build_seconds
              raise KeyError, "timing without build_seconds: #{timing.task.name} (#{timing.task.group})"
            end
          end

          key = [ruby_version, gemfile]
          (gemfile_samples[key] ||= []) << timings.sum(&:build_seconds)
        end
      end

      new(manifest_from(task_samples, gemfile_samples))
    end

    def empty?
      @manifest.fetch("ruby_versions", {}).empty?
    end

    def for_ruby(ruby_version)
      Ruby.new(@manifest.fetch("ruby_versions", {}).fetch(ruby_version, {}))
    end

    def to_h
      @manifest
    end

    # Costs for one Ruby version, with quartile fallbacks for anything
    # without history.
    class Ruby
      def initialize(entries)
        @task_costs = entries.fetch("tasks", []).map { |entry| [[entry.fetch("task"), entry.fetch("group")], entry.fetch("p90_seconds")] }.to_h
        @gemfile_costs = entries.fetch("gemfiles", []).map { |entry| [entry.fetch("gemfile"), entry.fetch("p90_seconds")] }.to_h
      end

      def test_cost(task)
        @task_costs.fetch([task.name, task.group], fallback_for_tasks)
      end

      def setup_cost(gemfile_name)
        @gemfile_costs.fetch(gemfile_name, fallback_for_gemfiles)
      end

      private

      def fallback_for_tasks
        @fallback_for_tasks ||= quartile(@task_costs.values)
      end

      def fallback_for_gemfiles
        @fallback_for_gemfiles ||= quartile(@gemfile_costs.values)
      end

      # Upper quartile of the known durations, or a minute when nothing is
      # known yet.
      def quartile(durations)
        sorted = durations.sort
        return 60.0 if sorted.empty?

        sorted[(sorted.length * 0.75).floor]
      end
    end

    # The null weights: no manifest exists yet, so every cost falls back and
    # batching stays static.
    class Missing < self
      def initialize
        super({})
      end
    end

    def self.manifest_from(task_samples, gemfile_samples)
      ruby_versions = task_samples.keys.map(&:first).uniq.sort.each_with_object({}) do |ruby_version, versions|
        tasks = task_samples.select { |key, _| key.first == ruby_version }.map do |key, values|
          _, name, group = key

          Samples.new(values).to_h.merge("task" => name, "group" => group)
        end
        gemfiles = gemfile_samples.select { |key, _| key.first == ruby_version }.map do |key, values|
          _, gemfile = key

          Samples.new(values).to_h.merge("gemfile" => gemfile)
        end

        versions[ruby_version] = {
          "tasks" => tasks.sort_by { |entry| [entry.fetch("task"), entry.fetch("group")] },
          "gemfiles" => gemfiles.sort_by { |entry| entry.fetch("gemfile") },
        }
      end

      {"ruby_versions" => ruby_versions}
    end

    private_class_method :manifest_from
  end

  # Filesystem adapter for the Weights stage.
  module ManifestStore
    MANIFEST_PATH = "tmp/ci_task_timings.json"

    module_function

    # Aggregates every timing document in a directory into the manifest at
    # MANIFEST_PATH. Raises when the directory holds no timing files so the
    # scheduled workflow fails loudly instead of publishing empty weights.
    def update_from(directory)
      runs = TimingFiles.read_all(directory)
      raise "no timing files found in #{directory}" if runs.empty?

      write(Weights.from(runs))
    end

    def write(weights, path: MANIFEST_PATH)
      File.write(path, JSON.pretty_generate(weights.to_h) + "\n")
    end
    private_class_method :write

    # Returns Weights::Missing when no readable manifest exists, so callers
    # can keep batching statically until the cache bootstraps.
    def load(path: MANIFEST_PATH)
      Weights.new(JSON.parse(File.read(path)))
    rescue Errno::ENOENT, JSON::ParserError => e
      warn "Could not read the weights manifest at #{path} (#{e.class}: #{e.message}); continuing without one"

      Weights::Missing.new
    end
  end
end
