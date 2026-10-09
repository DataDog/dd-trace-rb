# frozen_string_literal: true

require_relative "../../appraisal_conversion"
require_relative "task"

# The Matrixfile as task objects: which tasks run under which Ruby, and which
# of them need dedicated service containers instead of batching.
module TestBatching
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
