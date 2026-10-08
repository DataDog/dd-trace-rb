require "json"

module GithubBatching
  WEIGHTS_URL = "https://raw.githubusercontent.com/TonyCTHsu/dd-test-weights/main/ci_task_timings.json"

  module_function

  def timing_estimates(ruby_version, url: WEIGHTS_URL)
    entries = (fetch_weights(url) || {}).fetch("ruby_versions", {}).fetch(ruby_version, {})

    {
      tasks: entries.fetch("tasks", []).map do |entry|
        [[entry.fetch("task"), entry.fetch("group")], entry.fetch("p90_seconds")]
      end.to_h,
      gemfiles: entries.fetch("gemfiles", []).map do |entry|
        [entry.fetch("gemfile"), entry.fetch("p90_seconds")]
      end.to_h,
    }
  end

  def fetch_weights(url)
    require "open-uri"

    JSON.parse(URI(url).open(open_timeout: 5, read_timeout: 10, &:read))
  rescue => e
    warn "Falling back to checked-in task timings: could not fetch #{url} (#{e.class}: #{e.message})"
    nil
  end

  def aggregate_timing_files(paths)
    task_samples = {}
    gemfile_samples = {}

    paths.each do |path|
      data = JSON.parse(File.read(path))
      ruby_version = data.fetch("ruby_version")
      tasks = data.fetch("tasks")

      tasks.each do |task|
        key = [ruby_version, task.fetch("task"), task.fetch("group")]
        task_samples[key] ||= []
        task_samples[key] << task.fetch("test_seconds")
      end

      tasks.group_by { |task| File.basename(task.fetch("gemfile")) }.each do |gemfile, grouped_tasks|
        key = [ruby_version, gemfile]
        gemfile_samples[key] ||= []
        gemfile_samples[key] << grouped_tasks.sum { |task| task.fetch("build_seconds") }
      end
    end

    ruby_versions = task_samples.keys.map(&:first).uniq.sort.each_with_object({}) do |ruby_version, versions|
      tasks = task_samples.select { |key, _| key.first == ruby_version }.map do |key, durations|
        _, task, group = key
        duration_estimates(durations).merge("task" => task, "group" => group)
      end
      gemfiles = gemfile_samples.select { |key, _| key.first == ruby_version }.map do |key, durations|
        _, gemfile = key
        duration_estimates(durations).merge("gemfile" => gemfile)
      end

      versions[ruby_version] = {
        "tasks" => tasks.sort_by { |entry| [entry.fetch("task"), entry.fetch("group")] },
        "gemfiles" => gemfiles.sort_by { |entry| entry.fetch("gemfile") },
      }
    end

    {"ruby_versions" => ruby_versions}
  end

  def distribute(tasks, estimates, batch_count)
    task_estimates = estimates.fetch(:tasks)
    gemfile_estimates = estimates.fetch(:gemfiles)
    task_fallback = fallback_duration(task_estimates.values)
    gemfile_fallback = fallback_duration(gemfile_estimates.values)
    weighted_tasks = tasks.map do |task|
      key = [task.fetch(:task).to_s, task.fetch(:group).to_s]
      gemfile = File.basename(task.fetch(:gemfile))
      {
        task: task,
        gemfile: gemfile,
        test_seconds: task_estimates.fetch(key, task_fallback),
        setup_seconds: gemfile_estimates.fetch(gemfile, gemfile_fallback),
      }
    end

    groups = weighted_tasks.group_by { |entry| entry.fetch(:gemfile) }.map do |gemfile, entries|
      entries.sort_by! do |entry|
        task = entry.fetch(:task)
        [-entry.fetch(:test_seconds), task.fetch(:task).to_s, task.fetch(:group).to_s]
      end
      {
        gemfile: gemfile,
        tasks: entries,
        seconds: entries.sum { |entry| entry.fetch(:test_seconds) } + entries.first.fetch(:setup_seconds),
      }
    end
    groups.sort_by! { |group| [-group.fetch(:seconds), group.fetch(:gemfile)] }

    batches = Array.new(batch_count) { {tasks: [], gemfiles: {}, seconds: 0.0} }
    groups.each do |group|
      index = batches.each_index.min_by { |candidate| [batches[candidate][:seconds], candidate] }
      batches[index][:tasks].concat(group.fetch(:tasks))
      batches[index][:gemfiles][group.fetch(:gemfile)] = group.fetch(:tasks).length
      batches[index][:seconds] += group.fetch(:seconds)
    end

    improve_batches(batches)

    batches.map do |batch|
      {
        tasks: batch.fetch(:tasks).map { |entry| entry.fetch(:task) },
        seconds: batch.fetch(:seconds),
      }
    end
  end

  def improve_batches(batches)
    loop do
      current_max = batches.map { |batch| batch.fetch(:seconds) }.max
      best = nil

      batches.each_with_index do |source, source_index|
        next unless source.fetch(:seconds) == current_max

        source.fetch(:tasks).each_with_index do |entry, task_index|
          batches.each_with_index do |destination, destination_index|
            next if source_index == destination_index

            gemfile = entry.fetch(:gemfile)
            source_seconds = source.fetch(:seconds) - entry.fetch(:test_seconds)
            source_seconds -= entry.fetch(:setup_seconds) if source.fetch(:gemfiles).fetch(gemfile) == 1
            destination_seconds = destination.fetch(:seconds) + entry.fetch(:test_seconds)
            destination_seconds += entry.fetch(:setup_seconds) unless destination.fetch(:gemfiles).key?(gemfile)
            candidate_max = batches.each_index.map do |index|
              if index == source_index
                source_seconds
              elsif index == destination_index
                destination_seconds
              else
                batches[index].fetch(:seconds)
              end
            end.max

            task = entry.fetch(:task)
            candidate = [
              candidate_max,
              task.fetch(:task).to_s,
              task.fetch(:group).to_s,
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
      gemfile = entry.fetch(:gemfile)

      source.fetch(:gemfiles)[gemfile] -= 1
      source.fetch(:gemfiles).delete(gemfile) if source.fetch(:gemfiles).fetch(gemfile) == 0
      destination.fetch(:tasks) << entry
      destination.fetch(:gemfiles)[gemfile] = destination.fetch(:gemfiles).fetch(gemfile, 0) + 1
      source[:seconds] = source_seconds
      destination[:seconds] = destination_seconds
    end
  end

  def fallback_duration(durations)
    sorted = durations.sort
    return 60.0 if sorted.empty?

    sorted[(sorted.length * 0.75).floor]
  end

  def median(values)
    sorted = values.sort
    middle = sorted.length / 2
    return sorted[middle] if sorted.length.odd?

    (sorted[middle - 1] + sorted[middle]) / 2.0
  end

  def duration_estimates(values)
    sorted = values.sort
    p90_index = ((sorted.length - 1) * 0.9).ceil
    {
      "p50_seconds" => median(sorted).round(3),
      "p90_seconds" => sorted.fetch(p90_index).round(3),
      "samples" => sorted.length,
    }
  end
  private_class_method :duration_estimates, :fallback_duration, :fetch_weights, :improve_batches, :median
end
