# Runs without Bundler.
require "json"
require_relative "appraisal_conversion"

# rubocop:disable Metrics/BlockLength
namespace :github do
  task :generate_batches do
    matrix = eval(File.read("Matrixfile"), binding, "Matrixfile").freeze # rubocop:disable Security/Eval
    all_tasks = matrix.each_with_object([]) do |(key, spec_metadata), tasks|
      spec_metadata.each do |group, rubies|
        next unless rubies.include?("✅ #{RUBY_VERSION[0..2]}")

        gemfile = begin
          AppraisalConversion.to_bundle_gemfile(group)
        rescue
          AppraisalConversion.parent_gemfile
        end
        tasks << {task: key, group: group, gemfile: gemfile}
      end
    end
    misc_tasks, matching_tasks = all_tasks.partition do |task|
      %w[mongodb elasticsearch opensearch presto dalli].include?(task[:task])
    end
    batch_count = 7

    tasks_per_job = (matching_tasks.size.to_f / batch_count).ceil

    batched_matrix = {"include" => []}

    matching_tasks.each_slice(tasks_per_job).with_index do |task_group, index|
      batched_matrix["include"] << {"batch" => index.to_s, "tasks" => task_group}
    end

    data = {
      batches: batched_matrix,
      misc: {"include" => [{"batch" => "0", "tasks" => misc_tasks}]},
      all: all_tasks,
      gemfiles: all_tasks.map { |task| task[:gemfile] }.uniq.sort,
    }

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
          <summary>Batch #{batch["batch"]} (#{batch["tasks"].length} tasks)</summary>

          #{rows.join("\n")}
          </details>
        SUMMARY
      end
    end
  end

  task :run_batch_build do
    tasks = JSON.parse(ENV.fetch("BATCHED_TASKS"))
    base_gemfile = File.expand_path(ENV.fetch("BUNDLE_GEMFILE", "Gemfile"))

    tasks.uniq { |task| task.fetch("gemfile") }.each do |task|
      next if File.expand_path(task.fetch("gemfile")) == base_gemfile

      env = {"BUNDLE_GEMFILE" => task.fetch("gemfile")}
      # Network failures can interrupt bundle installation.
      with_retry do
        Bundler.with_unbundled_env { sh(env, "bundle check || bundle install") }
      end
    end
  end

  task :check_matrix_bundle do
    base_gemfile = File.expand_path(ENV.fetch("BUNDLE_GEMFILE"))
    gemfiles = JSON.parse(ENV.fetch("GEMFILES"))
    gemfiles.uniq { |gemfile| File.expand_path(gemfile) }.each do |gemfile|
      next if File.expand_path(gemfile) == base_gemfile

      Bundler.with_unbundled_env { sh({"BUNDLE_GEMFILE" => gemfile}, "bundle check") }
    end
  end

  task :run_batch_tests do
    tasks = JSON.parse(ENV["BATCHED_TASKS"] || {})

    rng = Random.new(ENV["CI_TEST_SEED"].to_i)

    durations = tasks.map do |task|
      env = {"BUNDLE_GEMFILE" => task["gemfile"]}
      cmd = "bundle exec rake spec:#{task["task"]}'[--seed #{rng.rand(0xFFFF)}]'"

      junit_files_before = Dir["tmp/rspec/*.xml"]

      begin
        Bundler.with_unbundled_env { sh(env, cmd) }
      rescue RuntimeError
        raise annotate_test_failures(env, cmd)
      end

      junit_files_after = Dir["tmp/rspec/*.xml"] - junit_files_before

      [task["task"], junit_files_after.sum { |file| junit_suite_time(file) }]
    end

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
