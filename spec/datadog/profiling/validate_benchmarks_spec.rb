require "datadog/profiling/spec_helper"

RSpec.describe "Profiling benchmarks", :memcheck_valgrind_skip do
  before do
    skip_if_profiling_not_supported
  end

  with_env "VALIDATE_BENCHMARK" => "true", "DD_TRACE_STARTUP_LOGS" => "true"

  benchmarks_to_validate = [
    "profiling_allocation",
    "profiling_gc",
    "profiling_hold_resume_interruptions",
    "profiling_http_transport",
    "profiling_memory_sample_serialize",
    "profiling_sample_loop_v2",
    "profiling_sample_serialize",
    "profiling_sample_gvl",
    "profiling_sample_overhead",
    "profiling_string_storage_intern",
  ].freeze

  benchmarks_to_validate.each do |benchmark|
    describe benchmark do
      let!(:memory_before_benchmark) { macos_memory_snapshot if PlatformHelpers.mac? }

      after do |example|
        next unless example.exception && PlatformHelpers.mac?

        warn "macOS memory before #{benchmark}:\n#{memory_before_benchmark}"
        warn "macOS memory after failure in #{benchmark}:\n#{macos_memory_snapshot}"

        begin
          # Diagnostics for when this fails in CI
          warn "macOS system logs after failure in #{benchmark}:"
          # We use "sudo -n" which fails if sudo would ask for a password instead of prompting
          success = system(%q(sudo -n /usr/bin/log show --last 2m --style compact --predicate 'process == "kernel" OR process == "syspolicyd" OR process == "taskgated"'))
          warn "Unable to collect macOS system logs" unless success
        rescue => e
          warn "Unable to collect macOS system logs: #{e.class}: #{e.message}"
        end
      end

      it("runs without raising errors") { expect_in_fork(timeout_seconds: 15, trigger_stacktrace_on_kill: true) { load "./benchmarks/#{benchmark}.rb" } }
    end
  end

  # This test validates that we don't forget to add new benchmarks to benchmarks_to_validate
  it "tests all expected benchmarks in the benchmarks folder" do
    all_benchmarks = Dir["./benchmarks/profiling_*"].map { |it| it.gsub("./benchmarks/", "").gsub(".rb", "") }

    expect(benchmarks_to_validate).to contain_exactly(*all_benchmarks)
  end

  def macos_memory_snapshot
    [
      "/usr/bin/vm_stat",
      "/usr/bin/memory_pressure",
      "/usr/sbin/sysctl vm.swapusage",
      "/bin/ps -A -m -o pid,ppid,rss,comm",
    ].map do |command|
      captured = `#{command} 2>&1`
      result = "#{command} (#{$?.inspect}):\n#{captured}"
      raise "Command failed: #{result}" unless $?.success?

      result
    end.join("\n")
  end
end
