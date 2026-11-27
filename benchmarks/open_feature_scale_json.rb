# Used to quickly run benchmark under RSpec as part of the usual test suite, to validate it didn't bitrot
VALIDATE_BENCHMARK_MODE = ENV["VALIDATE_BENCHMARK"] == "true"

return unless __FILE__ == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

require "json"
require_relative "benchmarks_helper"
require_relative "../tasks/lib/fixtures/ffe"
require "datadog/open_feature/evaluation_engine"
require "datadog/open_feature/provider"

# Benchmarks flag evaluation through Provider#fetch_*_value on the shared FFE scale suites:
#   1. scale-json: JSON variant values from 330 bytes to 4.5 MB, for the first evaluation after a
#      configuration load and for a repeat evaluation of the same flag, with time and allocated objects;
#   2. scale: targeting at large N, one report per case file, rotating through its cases.
#
# spec/datadog/open_feature/scale_suites_spec.rb checks every expected result. This file checks each
# case once more before it measures. The provider needs openfeature-sdk, so run it with an OpenFeature
# appraisal after `bundle exec rake fixtures:ffe:download`:
#
#   BUNDLE_GEMFILE=gemfiles/ruby_4.0_openfeature_latest.gemfile bundle exec ruby benchmarks/open_feature_scale_json.rb
class OpenFeatureScaleJsonBenchmark
  # Errors fail the case check below, so the benchmark never needs to report them.
  class NoopTelemetry
    def report(_error, description:)
      # no-op
    end
  end

  FETCH_METHODS = {
    "BOOLEAN" => :fetch_boolean_value,
    "STRING" => :fetch_string_value,
    "INTEGER" => :fetch_integer_value,
    "NUMERIC" => :fetch_number_value,
    "JSON" => :fetch_object_value,
  }.freeze

  FIRST_EVALUATION_SAMPLES = 10
  REPEAT_EVALUATION_SAMPLES = 20

  ScaleCase = Struct.new(:name, :test_case, :evaluation_context)

  def benchmark_time(time: 5, warmup: 1)
    VALIDATE_BENCHMARK_MODE ? {time: 0.001, warmup: 0} : {time: time, warmup: warmup}
  end

  def benchmark_results_file(suffix)
    "#{File.basename(__FILE__, ".rb")}-#{suffix}-results.json"
  end

  def initialize
    @fixture_root = File.join(File.expand_path("..", __dir__), FfeFixtures::CACHE, FfeFixtures::COMMIT_SHA)
    unless File.directory?(@fixture_root)
      raise "FFE fixtures are not cached under #{@fixture_root}. Run: bundle exec rake fixtures:ffe:download"
    end

    @engine = Datadog::OpenFeature::EvaluationEngine.new(telemetry: NoopTelemetry.new, logger: Datadog.logger)
    engine = @engine
    # The provider reads the engine from the component tree; building that tree would start the
    # configuration delivery and exposure workers, which this benchmark does not measure.
    Datadog::OpenFeature.define_singleton_method(:engine) { engine }
    @provider = Datadog::OpenFeature::Provider.new(experimentation_opt_out_mode: :disabled)
  end

  def suite_configuration(suite)
    File.read(File.join(@fixture_root, "evaluation-suites", suite, "ufc-config.json"))
  end

  # Returns {case file basename => [ScaleCase]} for the suite.
  def suite_cases(suite)
    Dir[File.join(@fixture_root, "evaluation-suites", suite, "cases", "*.json")].sort.to_h do |case_file|
      dimension = File.basename(case_file, ".json")
      test_cases = JSON.parse(File.read(case_file)).select { |test_case| FfeFixtures.applicable?(test_case, platform: "ruby") }
      scale_cases = test_cases.map do |test_case|
        attributes = test_case.fetch("attributes") || {}
        name = "#{suite}/#{dimension}/#{test_case.fetch("flag")}"
        name += " #{attributes.map { |key, value| "#{key}=#{value}" }.join(",")}" unless attributes.empty?
        context = ::OpenFeature::SDK::EvaluationContext.new(targeting_key: test_case["targetingKey"], **attributes)
        ScaleCase.new(name, test_case, context)
      end
      [dimension, scale_cases]
    end
  end

  def evaluate(scale_case)
    test_case = scale_case.test_case
    @provider.public_send(
      FETCH_METHODS.fetch(test_case.fetch("variationType")),
      flag_key: test_case.fetch("flag"),
      default_value: test_case.fetch("defaultValue"),
      evaluation_context: scale_case.evaluation_context,
    )
  end

  def check!(scale_case)
    result = evaluate(scale_case)
    expected = scale_case.test_case.fetch("result")
    return if result.value == expected.fetch("value") && result.reason == expected.fetch("reason")

    raise "#{scale_case.name}: got reason #{result.reason.inspect} (#{result.error_message.inspect}), " \
      "expected #{expected.fetch("reason").inspect} and the fixture value"
  end

  # Returns [seconds, allocated objects] for one evaluation.
  def measure(scale_case)
    allocated_before = GC.stat(:total_allocated_objects)
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    evaluate(scale_case)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
    [elapsed, GC.stat(:total_allocated_objects) - allocated_before]
  end

  def median(values)
    sorted = values.sort
    middle = sorted.length / 2
    sorted.length.odd? ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2.0
  end

  # The first evaluation after each configuration load is timed alone: reconfigure! runs outside the sample.
  def benchmark_scale_json_first_and_repeat
    configuration = suite_configuration("scale-json")
    scale_cases = suite_cases("scale-json").values.flatten
    first_samples = VALIDATE_BENCHMARK_MODE ? 1 : FIRST_EVALUATION_SAMPLES
    repeat_samples = VALIDATE_BENCHMARK_MODE ? 1 : REPEAT_EVALUATION_SAMPLES

    @engine.reconfigure!(configuration)
    scale_cases.each { |scale_case| check!(scale_case) }

    rows = scale_cases.map do |scale_case|
      first = Array.new(first_samples) do
        @engine.reconfigure!(configuration)
        measure(scale_case)
      end
      evaluate(scale_case)
      repeat = Array.new(repeat_samples) { measure(scale_case) }
      value_bytes = JSON.generate(scale_case.test_case.fetch("result").fetch("value")).bytesize

      {
        "case" => scale_case.name,
        "value_bytes" => value_bytes,
        "first_ms" => median(first.map(&:first)) * 1000,
        "first_allocated_objects" => median(first.map(&:last)),
        "repeat_ms" => median(repeat.map(&:first)) * 1000,
        "repeat_allocated_objects" => median(repeat.map(&:last)),
      }
    end

    print_rows(rows)
    File.write(benchmark_results_file("first-and-repeat"), JSON.pretty_generate(rows)) unless VALIDATE_BENCHMARK_MODE
  end

  def print_rows(rows)
    header = ["bytes", "first ms", "first objs", "repeat ms", "repeat objs"]
    puts "case".ljust(58) + header.zip([10, 11, 12, 11, 12]).map { |label, width| " #{label.rjust(width)}" }.join
    rows.each do |row|
      puts format(
        "%-58s %10d %11.3f %12d %11.3f %12d",
        row["case"], row["value_bytes"], row["first_ms"], row["first_allocated_objects"],
        row["repeat_ms"], row["repeat_allocated_objects"],
      )
    end
  end

  def benchmark_scale_json_repeat
    @engine.reconfigure!(suite_configuration("scale-json"))
    scale_cases = suite_cases("scale-json").values.flatten
    scale_cases.each { |scale_case| check!(scale_case) }

    Benchmark.ips do |x|
      x.config(**benchmark_time)

      scale_cases.each do |scale_case|
        x.report("repeat/#{scale_case.name}") { evaluate(scale_case) }
      end

      x.save!(benchmark_results_file("scale-json-repeat")) unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end
  end

  def benchmark_scale
    @engine.reconfigure!(suite_configuration("scale"))
    cases_by_dimension = suite_cases("scale")
    cases_by_dimension.each_value { |scale_cases| scale_cases.each { |scale_case| check!(scale_case) } }

    Benchmark.ips do |x|
      x.config(**benchmark_time(time: 2))

      cases_by_dimension.each do |dimension, scale_cases|
        counter = 0
        x.report("scale/#{dimension} (#{scale_cases.length} cases, rotated)") do
          evaluate(scale_cases[counter % scale_cases.length])
          counter += 1
        end
      end

      x.save!(benchmark_results_file("scale")) unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end
  end
end

puts "Current pid is #{Process.pid}"

def run_benchmark(&block)
  if VALIDATE_BENCHMARK_MODE
    block.call
  else
    # Forking to avoid state leaking between benchmarks
    pid = fork(&block)
    _, status = Process.wait2(pid)

    raise "Benchmark failed with status #{status}" unless status.success?
  end
end

OpenFeatureScaleJsonBenchmark.new.instance_exec do
  run_benchmark { benchmark_scale_json_first_and_repeat }
  run_benchmark { benchmark_scale_json_repeat }
  run_benchmark { benchmark_scale }
end
