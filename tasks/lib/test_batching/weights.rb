# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "timings"

# The Weights stage: what history taught. Weights learns the durations from
# many runs' timings, answers cost queries per Ruby, and owns its manifest
# file: the ci_task_timings.json the scheduled workflow publishes and the
# batch job consumes.
module TestBatching
  class Weights
    MANIFEST_PATH = "tmp/ci_task_timings.json"

    def initialize(manifest)
      @manifest = manifest
    end

    def self.from(runs)
      task_samples = {}
      gemfile_samples = {}

      runs.each do |run_timings|
        ruby_version = run_timings.ruby_version

        run_timings.timings.each do |entry|
          task_name = entry.fetch("task")
          group = entry.fetch("group")

          test_seconds = entry.fetch("test_seconds")
          (task_samples[[ruby_version, task_name, group]] ||= []) << test_seconds
        end

        run_timings.timings.group_by { |entry| File.basename(entry.fetch("gemfile")) }.each do |gemfile, entries|
          (gemfile_samples[[ruby_version, gemfile]] ||= []) << entries.sum { |entry| entry.fetch("build_seconds") }
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

    # Aggregates every timing document in a directory into the manifest at
    # MANIFEST_PATH. Raises when the directory holds no timing files so the
    # scheduled workflow fails loudly instead of publishing empty weights.
    def self.aggregate(directory)
      runs = RunTimings.read_all(directory)
      raise "no timing files found in #{directory}" if runs.empty?

      FileUtils.mkdir_p(File.dirname(MANIFEST_PATH))
      File.write(MANIFEST_PATH, JSON.pretty_generate(from(runs).to_h) + "\n")
    end

    # Returns empty weights when no readable manifest exists, so callers
    # can keep batching statically until the cache bootstraps.
    def self.load(path: MANIFEST_PATH)
      new(JSON.parse(File.read(path)))
    rescue Errno::ENOENT, JSON::ParserError => e
      warn "Could not read the weights manifest at #{path} (#{e.class}: #{e.message}); continuing without one"

      new({})
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
    private_constant :Ruby

    def self.manifest_from(task_samples, gemfile_samples)
      ruby_versions = task_samples.keys.map(&:first).uniq.sort.each_with_object({}) do |ruby_version, versions|
        tasks = task_samples.select { |key, _| key.first == ruby_version }.map do |key, values|
          _, name, group = key

          percentiles(values).merge("task" => name, "group" => group)
        end
        gemfiles = gemfile_samples.select { |key, _| key.first == ruby_version }.map do |key, values|
          _, gemfile = key

          percentiles(values).merge("gemfile" => gemfile)
        end

        versions[ruby_version] = {
          "tasks" => tasks.sort_by { |entry| [entry.fetch("task"), entry.fetch("group")] },
          "gemfiles" => gemfiles.sort_by { |entry| entry.fetch("gemfile") },
        }
      end

      {"ruby_versions" => ruby_versions}
    end

    # Percentile summary of one task's or Gemfile's observed durations:
    # p50 for diagnostics, p90 for scheduling.
    def self.percentiles(values)
      sorted = values.sort
      middle = sorted.length / 2
      p50 = if sorted.length.odd?
        sorted[middle]
      else
        (sorted[middle - 1] + sorted[middle]) / 2.0
      end
      p90 = sorted.fetch(((sorted.length - 1) * 0.9).ceil)

      {"p50_seconds" => p50.round(3), "p90_seconds" => p90.round(3), "samples" => sorted.length}
    end

    private_class_method :manifest_from, :percentiles
  end
end
