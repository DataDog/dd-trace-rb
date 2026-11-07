#
# Measures the cost of encoding Dynamic Instrumentation snapshot payloads
# with Datadog::DI::SnapshotEncoder, against JSON.dump of the same payload.
#
# The payloads are serialized by the DI serializer at default capture
# settings:
#
#   1.7 KB  - a method snapshot with a few small arguments; sent unpruned.
#   3.1 MB  - a return value of 100 arrays of 100 strings of 300 characters;
#             pruned to the size cap.
#   12.5 MB - four arguments like the 3.1 MB return value; pruned to the
#             size cap.
#
# JSON.dump does not prune, so for the pruned payloads its figure is the
# cost of encoding the whole payload.
#

# Used to quickly run benchmark under RSpec as part of the usual test suite, to validate it didn't bitrot
VALIDATE_BENCHMARK_MODE = ENV["VALIDATE_BENCHMARK"] == "true"

return unless __FILE__ == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

require "benchmark/ips"
require "json"
require "datadog"
require "datadog/di"
require "datadog/di/guardrails_telemetry"
require "datadog/di/logger"
require "datadog/di/redactor"
require "datadog/di/serializer"
require "datadog/di/snapshot_encoder"
require "datadog/di/transport/input"
require "logger"

class DISnapshotEncoderBenchmark
  CAP = Datadog::DI::Transport::Input::Transport::SNAPSHOT_SIZE_CAP

  def initialize
    settings = Datadog::Core::Configuration::Settings.new
    logger = Datadog::DI::Logger.new(settings, Logger.new(File::NULL))
    guardrails_telemetry = Datadog::DI::GuardrailsTelemetry.new(settings: settings, logger: logger, telemetry: nil)
    @serializer = Datadog::DI::Serializer.new(settings, Datadog::DI::Redactor.new(settings),
      logger: logger, guardrails_telemetry: guardrails_telemetry)
  end

  attr_reader :serializer

  def run_benchmark
    payloads = {
      "1.7 KB" => small_payload,
      "3.1 MB" => payload(return_value: matrix),
    }
    payloads["12.5 MB"] = payload(arguments: (1..4).map { |i| ["arg#{i}", matrix] }.to_h) unless VALIDATE_BENCHMARK_MODE

    payloads.each do |label, payload|
      raise "#{label} payload is #{JSON.dump(payload).bytesize} bytes" if label != "1.7 KB" && JSON.dump(payload).bytesize <= CAP
    end

    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? {time: 0.001, warmup: 0} : {time: 10, warmup: 2}
      x.config(**benchmark_time)

      payloads.each do |label, payload|
        x.report("SnapshotEncoder.encode - #{label}") { Datadog::DI::SnapshotEncoder.encode(payload, CAP) }
        x.report("JSON.dump - #{label}") { JSON.dump(payload) }
      end

      x.save! "#{File.basename(__FILE__, ".rb")}-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end
  end

  private

  def serialize(value)
    serializer.serialize_value(value, deadline: serializer.serialization_deadline)
  end

  def matrix
    Array.new(100) { Array.new(100) { "x" * 300 } }
  end

  def small_payload
    payload(
      arguments: {
        "name" => "alice",
        "count" => 3,
        "tags" => %w[admin beta],
        "options" => {verbose: true, retries: 2},
        "address" => {street: "1 Main Street", city: "Springfield", zip: "12345", country: "US"},
      },
      return_value: {status: "ok", items: [1, 2, 3]},
    )
  end

  def payload(arguments: {}, return_value: nil)
    {
      service: "di-snapshot-encoder-benchmark",
      debugger: {
        type: "snapshot",
        snapshot: {
          id: "00000000-0000-0000-0000-000000000001",
          timestamp: 1_700_000_000_000,
          evaluationErrors: [],
          probe: {id: "benchmark-probe", version: 0, location: {method: "run", type: "BenchmarkTarget"}},
          language: "ruby",
          stack: [{fileName: "/app/benchmark_target.rb", function: "run", lineNumber: 10}],
          captures: {
            entry: {arguments: arguments.transform_values { |value| serialize(value) }},
            return: {arguments: {"@return": serialize(return_value)}, throwable: nil},
          },
        },
      },
      duration: 1_000,
      host: nil,
      logger: {name: "/app/benchmark_target.rb", method_name: "run", thread_name: "main", thread_id: nil},
      runtime_id: "00000000-0000-0000-0000-000000000002",
      "dd.trace_id": nil,
      "dd.span_id": nil,
      ddsource: "dd_debugger",
      message: nil,
      timestamp: 1_700_000_000_000,
    }
  end
end

puts "Current pid is #{Process.pid}"

DISnapshotEncoderBenchmark.new.instance_exec do
  run_benchmark
end
