require "datadog/profiling/spec_helper"

RSpec.describe "Profiling benchmarks", :memcheck_valgrind_skip do
  before do
    skip_if_profiling_not_supported

    # @ivoanjo: We've seen these tests be flaky especially on Ruby 2.6: https://github.com/DataDog/dd-trace-rb/pull/4947
    # Even when trying to get a backtrace out of Ruby, all we saw was one of the Ruby threads sleeping
    # e.g. https://github.com/DataDog/dd-trace-rb/actions/runs/19484921634/job/55765012312#step:5:8980 :
    #
    # -- Control frame information -----------------------------------------------
    # c:0004 p:---- s:0014 e:000013 CFUNC  :sleep
    # c:0003 p:0005 s:0010 e:000009 BLOCK  /__w/dd-trace-rb/dd-trace-rb/benchmarks/profiling_sample_loop_v2.rb:16
    # c:0002 p:0011 s:0007 e:000006 BLOCK  /__w/dd-trace-rb/dd-trace-rb/spec/spec_helper.rb:290 [FINISH]
    # c:0001 p:---- s:0003 e:000002 (none) [FINISH]
    #
    # Because the objective of this spec is making sure the benchmarks don't bitrot, and seeing as this flakiness seems
    # to especially affect 2.6 but we have no indication otherwise that we have issues in Ruby 2.6, I decided to skip
    # this for now and rely on this spec running on other Ruby versions to validate the benchmark is ok.
    skip("Skipping on Ruby 2.6 as it's flaky and we couldn't figure out why yet") if RUBY_VERSION.start_with?("2.6")

    # Update: Because no good deed goes unpunished we also saw flakiness on 2.5 and actually that one provided NO
    # control frame information AND NO C level backtrace information -- so effectively no info.
    # For similar reasons as 2.6 above, I think this is at "let's keep an eye out on, and try to figure it out" level so
    # here's one more skip and let's hope that if/when this shows up on a modern Ruby we can get some actual interesting
    # info to debug.
    skip("Skipping on Ruby 2.5 as it's flaky and we couldn't figure out why yet") if RUBY_VERSION.start_with?("2.5")
  end

  with_env "VALIDATE_BENCHMARK" => "true"

  benchmarks_to_validate = [
    "profiling_allocation",
    "profiling_gc",
    "profiling_hold_resume_interruptions",
    "profiling_http_transport",
    "profiling_memory_sample_serialize",
    "profiling_sample_loop_v2",
    "profiling_sample_serialize",
    "profiling_sample_gvl",
    "profiling_string_storage_intern",
  ].freeze

  benchmarks_to_validate.each do |benchmark|
    describe benchmark do
      it("runs without raising errors") { expect_in_fork(timeout_seconds: 15, trigger_stacktrace_on_kill: true) { load "./benchmarks/#{benchmark}.rb" } }
    end
  end

  # This test validates that we don't forget to add new benchmarks to benchmarks_to_validate
  it "tests all expected benchmarks in the benchmarks folder" do
    all_benchmarks = Dir["./benchmarks/profiling_*"].map { |it| it.gsub("./benchmarks/", "").gsub(".rb", "") }

    expect(benchmarks_to_validate).to contain_exactly(*all_benchmarks)
  end
end
