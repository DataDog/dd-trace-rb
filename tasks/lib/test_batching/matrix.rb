# frozen_string_literal: true

require_relative "../../appraisal_conversion"

# The Matrix stage: the work that exists. A Task is one unit of it, and
# TaskMatrix is the Matrixfile as task objects, which also knows which tasks
# need dedicated service containers instead of batching.
module TestBatching
  # A unit of test work in the batch matrix, identified by name and group.
  # Equality ignores the Gemfile: the same task under a different Appraisal
  # still reports as one task.
  class Task
    attr_reader :name, :group, :gemfile

    def initialize(name:, group:, gemfile:)
      @name = name
      @group = group
      @gemfile = gemfile
    end

    def gemfile_name
      File.basename(gemfile)
    end

    def ==(other)
      other.is_a?(Task) && name == other.name && group == other.group
    end

    def hash
      [name, group].hash
    end
    alias_method :eql?, :==

    def to_h
      {"task" => name, "group" => group, "gemfile" => gemfile}
    end

    def self.from_h(hash)
      new(name: hash.fetch("task"), group: hash.fetch("group"), gemfile: hash.fetch("gemfile"))
    end
  end

  class TaskMatrix
    def initialize(matrix)
      @matrix = matrix
    end

    def batchable_tasks(ruby_version)
      tasks_for(ruby_version).reject { |task| misc?(task) }
    end

    def misc_tasks(ruby_version)
      tasks_for(ruby_version).select { |task| misc?(task) }
    end

    private

    # TODO: These are the exceptions, find a way to describe those service
    # dependencies in CI using a more generic mechanism.
    MISC_CANDIDATES = [
      "mongodb",
      "elasticsearch",
      "opensearch",
      "presto",
      "dalli",
    ].freeze
    private_constant :MISC_CANDIDATES

    def tasks_for(ruby_version)
      tasks = []

      @matrix.each do |name, spec_metadata|
        spec_metadata.each do |group, rubies|
          next unless rubies.include?("✅ #{ruby_version}")

          tasks << Task.new(name: name, group: group, gemfile: gemfile_for(group))
        end
      end

      tasks
    end

    def misc?(task)
      MISC_CANDIDATES.include?(task.name)
    end

    def gemfile_for(group)
      AppraisalConversion.to_bundle_gemfile(group)
    rescue
      AppraisalConversion.parent_gemfile
    end
  end
end
