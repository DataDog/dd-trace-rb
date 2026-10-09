# frozen_string_literal: true

# A unit of test work in the batch matrix, identified by name and group.
# Equality ignores the Gemfile: the same task under a different Appraisal
# still reports as one task.
module TestBatching
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
end
