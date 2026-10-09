# frozen_string_literal: true

require "json"
require_relative "batch_timing"
require_relative "task"
require_relative "timing_files"

# The process edge: runs the batch jobs' build and test steps, records their
# durations into BatchTiming documents, and reports results to the CI job
# (annotations + step summaries). The only module that runs commands, reads
# ENV, and prints.
module TestBatching
  module Runner
    module_function

    def build(tasks)
      batch_timing = BatchTiming.new(ruby_version: RUBY_VERSION[0..2], timings: [])

      tasks.map { |hash| Task.from_h(hash) }.each do |task|
        env = {"BUNDLE_GEMFILE" => task.gemfile}
        cmd = "bundle check || bundle install"
        # Retry mechanism to improve reliability in Github Actions,
        # since network issues can cause `bundle install` to fail.
        duration = measure_duration do
          with_retry do
            Bundler.with_unbundled_env { run_command(env, cmd) }
          end
        end

        batch_timing = batch_timing.with_timing(TaskTiming.new(task: task, build_seconds: duration))
      end

      TimingFiles.write(batch_timing)
    end

    def tests(tasks)
      rng = Random.new(ENV["CI_TEST_SEED"].to_i)
      tasks = tasks.map { |hash| Task.from_h(hash) }

      batch_timing = TimingFiles.read(tasks)

      durations = tasks.map do |task|
        env = {"BUNDLE_GEMFILE" => task.gemfile}
        cmd = "bundle exec rake spec:#{task.name}'[--seed #{rng.rand(0xFFFF)}]'"

        junit_files_before = Dir["tmp/rspec/*.xml"]

        test_seconds = measure_duration do
          Bundler.with_unbundled_env { run_command(env, cmd) }
        rescue RuntimeError
          raise annotate_test_failures(env, cmd)
        end

        junit_files_after = Dir["tmp/rspec/*.xml"] - junit_files_before
        junit_seconds = junit_files_after.sum { |file| junit_suite_time(file) }

        prior = batch_timing.find(task)
        batch_timing = batch_timing.with_timing(TaskTiming.new(
          task: task,
          build_seconds: prior&.build_seconds,
          test_seconds: test_seconds,
          junit_seconds: junit_seconds
        ))

        [task.name, junit_seconds]
      end

      TimingFiles.write(batch_timing)
      report_task_durations(durations)
    end

    def write_batch_summary(batches_json)
      raise "batches_json environment variable not set" unless batches_json

      data = JSON.parse(batches_json)
      summary = ENV["GITHUB_STEP_SUMMARY"]

      File.open(summary, "a") do |f|
        data["include"].each do |batch|
          rows = batch["tasks"].map do |t|
            "* #{t["task"]} (#{t["group"]})"
          end

          # Static batches carry no estimate, so weighted ones add it.
          label = "Batch #{batch["batch"]} (#{batch["tasks"].length} tasks"
          label += ", #{batch["estimated_seconds"]} estimated seconds" if batch["estimated_seconds"]

          f.puts <<~SUMMARY
            <details>
            <summary>#{label})</summary>

            #{rows.join("\n")}
            </details>
          SUMMARY
        end
      end
    end

    def annotate_test_failures(env, cmd)
      env_prefix = env.map { |k, v| "#{k}=#{v}" }.join(" ")
      repro_command = "#{env_prefix} #{cmd}"

      file = ENV.fetch("RSPEC_FAILURES_FILE", "tmp/rspec/failures.txt")
      return "RSpec failure" unless File.exist?(file)

      content = File.read(file)
      return "RSpec failure" if content.strip.empty?

      # GitHub Actions truncates large annotations in the UI, so above this
      # size fall back to failed example titles only.
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
        warn(
          "Bundle install failure (Attempt: #{retries + 1}): #{e.class.name}: #{e.message}, \
          Source:\n#{Array(e.backtrace).join("\n")}"
        )
        sleep(2**retries)
        retries += 1
        retry if retries < 3
        raise
      end
    end

    # `sh` equivalent: runs the command with the given environment and
    # raises RuntimeError when it fails. The manual raise replaces
    # `exception: true`, which Ruby 2.5 does not support.
    def run_command(env, cmd)
      return if system(env, cmd)

      raise "Command failed: #{cmd}"
    end

    private_class_method :annotate_test_failures, :escape_annotation, :junit_suite_time, :measure_duration,
      :report_task_durations, :run_command, :with_retry
  end
end
