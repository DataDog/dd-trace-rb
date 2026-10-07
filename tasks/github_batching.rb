require "json"

module GithubBatching
  module_function

  def timing_estimates(path, ruby_version)
    data = JSON.parse(File.read(path))
    entries = data.fetch("ruby_versions").fetch(ruby_version, [])

    entries.map { |entry| [[entry.fetch("task"), entry.fetch("group")], entry.fetch("seconds")] }.to_h
  end

  def aggregate_timing_files(paths)
    samples = {}

    paths.each do |path|
      data = JSON.parse(File.read(path))
      ruby_version = data.fetch("ruby_version")
      data.fetch("tasks").each do |task|
        key = [ruby_version, task.fetch("task"), task.fetch("group")]
        samples[key] ||= []
        samples[key] << task.fetch("build_seconds") + task.fetch("test_seconds")
      end
    end

    ruby_versions = samples.keys.map(&:first).uniq.sort.each_with_object({}) do |ruby_version, versions|
      entries = samples.select { |key, _| key.first == ruby_version }.map do |key, durations|
        _, task, group = key
        {"task" => task, "group" => group, "seconds" => median(durations).round(3)}
      end
      versions[ruby_version] = entries.sort_by { |entry| [entry.fetch("task"), entry.fetch("group")] }
    end

    {"ruby_versions" => ruby_versions}
  end

  def distribute(tasks, estimates, batch_count)
    fallback = fallback_duration(estimates.values)
    weighted_tasks = tasks.map do |task|
      key = [task.fetch(:task).to_s, task.fetch(:group).to_s]
      [task, estimates.fetch(key, fallback)]
    end
    weighted_tasks.sort_by! { |task, seconds| [-seconds, task.fetch(:task).to_s, task.fetch(:group).to_s] }

    batches = Array.new(batch_count) { {tasks: [], seconds: 0.0} }
    weighted_tasks.each do |task, seconds|
      index = batches.each_index.min_by { |candidate| [batches[candidate][:seconds], candidate] }
      batches[index][:tasks] << task
      batches[index][:seconds] += seconds
    end

    batches
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
  private_class_method :fallback_duration, :median
end
