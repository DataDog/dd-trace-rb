require "digest"
require "fileutils"
require "json"
require_relative "appraisal_conversion"
require_relative "github_batching"

# rubocop:disable Metrics/BlockLength
namespace :github do
  task :generate_batches do
    matrix = eval(File.read("Matrixfile")).freeze # rubocop:disable Security/Eval

    # TODO: These are the execptions, find a way to describe those service dependencies in CI using a more generic mechansim.
    misc_candidates = [
      "mongodb",
      "elasticsearch",
      "opensearch",
      "presto",
      "dalli",
    ]

    ruby_version = RUBY_VERSION[0..2]

    matching_tasks = []
    misc_tasks = []

    matrix.each do |key, spec_metadata|
      spec_metadata.each do |group, rubies|
        matched = rubies.include?("✅ #{ruby_version}")

        next unless matched

        gemfile = begin
          AppraisalConversion.to_bundle_gemfile(group)
        rescue
          AppraisalConversion.parent_gemfile
        end

        task = {task: key, group: group, gemfile: gemfile}

        if misc_candidates.include?(key)
          misc_tasks << task
        else
          matching_tasks << task
        end
      end
    end

    # Seed
    batch_count = 7

    batched_matrix = {"include" => []}

    timings_path = File.expand_path("ci_task_timings.json", __dir__)
    estimates = GithubBatching.timing_estimates(timings_path, ruby_version)
    task_groups = GithubBatching.distribute(matching_tasks, estimates, batch_count)

    task_groups.each_with_index do |task_group, index|
      batched_matrix["include"] << {
        "batch" => index.to_s,
        "tasks" => task_group.fetch(:tasks),
        "estimated_seconds" => task_group.fetch(:seconds).round(1),
      }
    end

    data = {
      batches: batched_matrix,
      misc: {"include" => [{"batch" => "0", "tasks" => misc_tasks}]},
    }

    # Output the JSON
    puts JSON.dump(data)
  end

  task :generate_batch_summary do
    batches_json = ENV["batches_json"]
    raise "batches_json environment variable not set" unless batches_json

    data = JSON.parse(batches_json)
    summary = ENV["GITHUB_STEP_SUMMARY"]

    File.open(summary, "a") do |f|
      data["include"].each do |batch|
        rows = batch["tasks"].map do |t|
          "* #{t["task"]} (#{t["group"]})"
        end

        f.puts <<~SUMMARY
          <details>
          <summary>Batch #{batch["batch"]} (#{batch["tasks"].length} tasks, #{batch["estimated_seconds"]} estimated seconds)</summary>

          #{rows.join("\n")}
          </details>
        SUMMARY
      end
    end
  end

  task :update_task_timings, [:directory] do |_, args|
    directory = args[:directory]
    raise "timings directory not provided" if directory.to_s.empty?

    paths = Dir[File.join(directory, "**", "*.json")]
    raise "no timing files found in #{directory}" if paths.empty?

    aggregate = GithubBatching.aggregate_timing_files(paths)
    path = File.expand_path("ci_task_timings.json", __dir__)
    File.write(path, JSON.pretty_generate(aggregate) + "\n")
  end

  task :run_batch_build do
    tasks = JSON.parse(ENV["BATCHED_TASKS"] || {})

    timings = tasks.map do |task|
      env = {"BUNDLE_GEMFILE" => task["gemfile"]}
      cmd = "bundle check || bundle install"
      # Retry mechanism to improve reliability in Github Actions,
      # since network issues can cause `bundle install` to fail.
      duration = measure_duration do
        with_retry do
          Bundler.with_unbundled_env { sh(env, cmd) }
        end
      end

      task.merge("build_seconds" => duration)
    end

    write_task_timings(tasks, timings)
  end

  task :run_batch_tests do
    tasks = JSON.parse(ENV["BATCHED_TASKS"] || {})

    rng = Random.new(ENV["CI_TEST_SEED"].to_i)

    timings = read_task_timings(tasks)

    durations = tasks.map do |task|
      env = {"BUNDLE_GEMFILE" => task["gemfile"]}
      cmd = "bundle exec rake spec:#{task["task"]}'[--seed #{rng.rand(0xFFFF)}]'"

      junit_files_before = Dir["tmp/rspec/*.xml"]

      test_seconds = measure_duration do
        Bundler.with_unbundled_env { sh(env, cmd) }
      rescue RuntimeError
        raise annotate_test_failures(env, cmd)
      end

      junit_files_after = Dir["tmp/rspec/*.xml"] - junit_files_before
      junit_seconds = junit_files_after.sum { |file| junit_suite_time(file) }

      timing = timings.find do |entry|
        entry.values_at("task", "group", "gemfile") == task.values_at("task", "group", "gemfile")
      end
      timing ||= task.dup
      timing["test_seconds"] = test_seconds
      timing["junit_seconds"] = junit_seconds
      timings << timing unless timings.include?(timing)

      [task["task"], junit_seconds]
    end

    write_task_timings(tasks, timings)
    report_task_durations(durations)
  end

  def annotate_test_failures(env, cmd)
    env_prefix = env.map { |k, v| "#{k}=#{v}" }.join(" ")
    repro_command = "#{env_prefix} #{cmd}"

    file = ENV.fetch("RSPEC_FAILURES_FILE", "tmp/rspec/failures.txt")
    return "RSpec failure" unless File.exist?(file)

    content = File.read(file)
    return "RSpec failure" if content.strip.empty?

    # GitHub Actions truncates large annotations in the UI; above this size,
    # fall back to failed example titles only.
    annotation_size_threshold = 4096

    title = escape_annotation("RSpec failure: #{repro_command}")

    summary = if content.bytesize <= annotation_size_threshold
      content
    else
      content[/^Failed examples:.*/m] || content
    end

    body = "#{title}\n\n#{summary}"
    puts "::error title=#{title}::#{escape_annotation(body)}"
    body
  end

  def escape_annotation(text)
    text.gsub("%", "%25").gsub("\r", "%0D").gsub("\n", "%0A")
  end

  def junit_suite_time(file)
    File.read(file)[/<testsuite\b[^>]*\btime="([\d.]+)"/, 1].to_f
  rescue Errno::ENOENT
    0.0
  end

  def measure_duration
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
  end

  def task_timings_path(tasks)
    identity = tasks.flat_map { |task| task.values_at("task", "group", "gemfile") }.join("\0")
    digest = Digest::SHA256.hexdigest(identity)[0, 12]
    "tmp/ci-task-timings/#{RUBY_VERSION[0..2]}-#{digest}.json"
  end

  def read_task_timings(tasks)
    path = task_timings_path(tasks)
    return [] unless File.exist?(path)

    JSON.parse(File.read(path)).fetch("tasks")
  end

  def write_task_timings(tasks, timings)
    path = task_timings_path(tasks)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.pretty_generate({"ruby_version" => RUBY_VERSION[0..2], "tasks" => timings}))
  end

  def report_task_durations(durations)
    summary = ENV["GITHUB_STEP_SUMMARY"]
    return if summary.to_s.empty?

    rows = durations.map { |(task, time)| "| #{task} | #{time.round(1)}s |" }

    File.open(summary, "a") do |f|
      f.puts <<~SUMMARY
        <details>
        <summary>Task durations</summary>

        | Task | Duration |
        | --- | --- |
        #{rows.join("\n")}
        </details>
      SUMMARY
    end
  end

  def with_retry(&block)
    retries = 0
    begin
      yield
    rescue => e
      rake_output_message(
        "Bundle install failure (Attempt: #{retries + 1}): #{e.class.name}: #{e.message}, \
        Source:\n#{Array(e.backtrace).join("\n")}"
      )
      sleep(2**retries)
      retries += 1
      retry if retries < 3
      raise
    end
  end
end
# rubocop:enable Metrics/BlockLength
