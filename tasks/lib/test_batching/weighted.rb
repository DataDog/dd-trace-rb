# frozen_string_literal: true

require_relative "batch"
require_relative "batch_plan"
require_relative "task_matrix"

# The weighted strategy: schedules tasks across batches by their learned
# durations. Gemfile groups stay together when splitting them makes the
# slowest batch slower, and split when the duplicated setup pays off.
module TestBatching
  class Weighted
    BATCH_COUNT = 7

    Entry = Struct.new(:task, :gemfile, :test_seconds, :setup_seconds, keyword_init: true)
    private_constant :Entry

    def initialize(ruby_weights, batch_count: BATCH_COUNT)
      @weights = ruby_weights
      @batch_count = batch_count
    end

    # Schedules in two phases.
    #
    # Phase one is LPT (Longest Processing Time): place the slowest remaining
    # Gemfile group on the lightest batch. LPT lands within 4/3 of the optimal
    # finish time, but it keeps groups whole and ignores setup costs.
    #
    # Phase two (improve) then trades setup for parallelism. It moves single
    # tasks between batches while doing so lowers the finish time, even when
    # the move duplicates a Gemfile setup in the destination batch.
    def plan(matrix, ruby_version)
      # Each entry pairs the task with its Gemfile and the weights that decide
      # placement: test duration plus the setup cost of that Gemfile.
      entries = matrix.batchable_tasks(ruby_version).map do |task|
        gemfile = task.gemfile_name

        Entry.new(
          task: task,
          gemfile: gemfile,
          test_seconds: @weights.test_cost(task),
          setup_seconds: @weights.setup_cost(gemfile)
        )
      end

      BatchPlan.new(batches: batches_from(entries), misc_tasks: matrix.misc_tasks(ruby_version))
    end

    private

    # Every batch slot, filled by phase one. The hashes are mutable scratch
    # state: improve rewrites them for every candidate move. One entry per
    # slot, empty ones included, keeps the workflow matrix at a constant
    # width.
    def batches_from(entries)
      groups = groups_from(entries)

      batches = Array.new(@batch_count) { {tasks: [], gemfiles: {}, seconds: 0.0} }
      groups.each do |group|
        # LPT: the slowest remaining group goes to the lightest batch, ties
        # preferring the lower index.
        index = batches.each_index.min_by { |candidate| [batches[candidate][:seconds], candidate] }
        batches[index][:tasks].concat(group.fetch(:tasks))
        batches[index][:gemfiles][group.fetch(:gemfile)] = group.fetch(:tasks).length
        batches[index][:seconds] += group.fetch(:seconds)
      end

      improve(batches)

      batches.map.with_index do |batch, index|
        # The mutable scratch state becomes immutable batches here, after
        # improve stops rewriting them.
        Batch.new(number: index, tasks: batch.fetch(:tasks).map(&:task), seconds: batch.fetch(:seconds))
      end
    end

    # One Gemfile's tasks, kept together: a batch pays each Gemfile's setup
    # once, so a group costs the sum of its tests plus that single setup.
    # Groups sort slowest-first and tasks within a group sort
    # slowest-test-first, both for phase one's greedy picks.
    def groups_from(entries)
      entries.group_by(&:gemfile).map do |gemfile, gemfile_entries|
        gemfile_entries.sort_by! { |entry| [-entry.test_seconds, entry.task.name, entry.task.group] }

        {
          gemfile: gemfile,
          tasks: gemfile_entries,
          seconds: gemfile_entries.sum(&:test_seconds) + gemfile_entries.first.setup_seconds,
        }
      end.sort_by! { |group| [-group[:seconds], group[:gemfile]] }
    end

    # Moves single tasks between batches while doing so lowers the slowest
    # batch. The slowest batch is the finish time, the wall-clock length of
    # the whole test run. Only its tasks are worth moving, since moving a
    # task out of any other batch cannot lower it.
    #
    # The accounting is exact. Removing a group's last task from a batch
    # frees that batch's setup for the Gemfile. Moving a task into a batch
    # that has never installed its Gemfile duplicates the setup there.
    #
    # Each iteration prices every (task, destination) pair in memory without
    # touching the batches, and keeps the best candidate, tie-broken
    # deterministically. The loop applies only moves that strictly lower the
    # finish time, so it terminates at a local optimum.
    def improve(batches)
      loop do
        current_max = batches.map { |batch| batch.fetch(:seconds) }.max
        best = nil

        batches.each_with_index do |source, source_index|
          next unless source.fetch(:seconds) == current_max

          source.fetch(:tasks).each_with_index do |entry, task_index|
            batches.each_with_index do |destination, destination_index|
              next if source_index == destination_index

              gemfile = entry.gemfile
              source_seconds = source.fetch(:seconds) - entry.test_seconds
              source_seconds -= entry.setup_seconds if source.fetch(:gemfiles).fetch(gemfile) == 1
              destination_seconds = destination.fetch(:seconds) + entry.test_seconds
              destination_seconds += entry.setup_seconds unless destination.fetch(:gemfiles).key?(gemfile)
              candidate_max = batches.each_index.map do |index|
                if index == source_index
                  source_seconds
                elsif index == destination_index
                  destination_seconds
                else
                  batches[index].fetch(:seconds)
                end
              end.max

              task = entry.task
              candidate = [
                candidate_max,
                task.name,
                task.group,
                source_index,
                destination_index,
                task_index,
                source_seconds,
                destination_seconds,
              ]
              best = candidate if best.nil? || (candidate.take(5) <=> best.take(5)) == -1
            end
          end
        end

        break if best.nil? || best.first >= current_max

        _, _, _, source_index, destination_index, task_index, source_seconds, destination_seconds = best
        source = batches.fetch(source_index)
        destination = batches.fetch(destination_index)
        entry = source.fetch(:tasks).delete_at(task_index)
        gemfile = entry.gemfile

        source.fetch(:gemfiles)[gemfile] -= 1
        source.fetch(:gemfiles).delete(gemfile) if source.fetch(:gemfiles).fetch(gemfile) == 0
        destination.fetch(:tasks) << entry
        destination.fetch(:gemfiles)[gemfile] = destination.fetch(:gemfiles).fetch(gemfile, 0) + 1
        source[:seconds] = source_seconds
        destination[:seconds] = destination_seconds
      end
    end
  end
end
