# frozen_string_literal: true

require_relative "batch_timing"
require_relative "samples"

# The aggregated weights: what CI knows about how long tasks and Gemfiles
# take, per Ruby. Built from batch timings. Answers cost queries. ManifestStore
# writes it to and reads it from the weights manifest.
module TestBatching
  class Weights
    def initialize(manifest)
      @manifest = manifest
    end

    def self.from(batch_timings)
      task_samples = {}
      gemfile_samples = {}

      batch_timings.each do |batch_timing|
        ruby_version = batch_timing.ruby_version

        batch_timing.timings.each do |timing|
          unless timing.test_seconds
            raise KeyError, "timing without test_seconds: #{timing.task.name} (#{timing.task.group})"
          end

          key = [ruby_version, timing.task.name, timing.task.group]
          (task_samples[key] ||= []) << timing.test_seconds
        end

        batch_timing.timings.group_by { |timing| timing.task.gemfile_name }.each do |gemfile, timings|
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
end
