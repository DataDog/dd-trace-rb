=begin

This benchmark verifies that the rate limits used for dynamic instrumentation
probes are attainable.

Each benchmark performs as many operations as the rate limit permits -
5000 for a basic probe and 1 for enriched probe. If the benchmark
produces a rate of fewer than 1 "instructions" per second, the rate limit is
not being reached. A result of more than 1 "instruction" per second
means the rate limit is being reached.

Note that the number of "instructions per second" reported by benchmark/ips
does not reflect how many times the instrumentation creates a snapshot -
there can (and normally are) invocations of the target method that do not
produce DI snapshots due to rate limit but these invocations are counted in
the "instructions per second" reported by benchmark/ips.

The default dynamic instrumentation settings for the probe notifier worker
(queue capacity of 100 and minimum send interval of 3 seconds) mean an
effective rate limit of 30 snapshots per second for basic probes,
which is shared across all probes in the application, which is significantly
below the 5000 snapshots per second per probe that DI is theoretically
supposed to achieve. However, to increase actual attainable snapshot rate
to 5000/second, the probe notifier worker needs to be changed to send
multiple network requests for a single queue processing run or be more
aggressive in flushing the snapshots to the network when the queue is getting
full. In either case care needs to be taken not to starve customer applications
of CPU.

=end

# Used to quickly run benchmark under RSpec as part of the usual test suite, to validate it didn't bitrot
VALIDATE_BENCHMARK_MODE = ENV['VALIDATE_BENCHMARK'] == 'true'

return unless __FILE__ == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

require 'benchmark/ips'
require 'datadog'
require 'webrick'

class DISnapshotBenchmark
  # If we are validating the benchmark a single operation is sufficient.
  BASIC_RATE_LIMIT = VALIDATE_BENCHMARK_MODE ? 1 : 5000
  ENRICHED_RATE_LIMIT = 1

  def initialize

    Datadog::DI.activate_tracking!

    Datadog.configure do |c|
      c.remote.enabled = true
      c.dynamic_instrumentation.enabled = true
      c.dynamic_instrumentation.internal.development = true

      # Increase queue capacity and reduce min send interval
      # to be able to send more snapshots out.
      # The default settings will result in dropped snapshots
      # way before non-enriched probe rate limit is reached.
      c.dynamic_instrumentation.internal.snapshot_queue_capacity = 10000
      c.dynamic_instrumentation.internal.min_send_interval = 1
    end

    Thread.new do
      # If there is an actual Datadog agent running locally, the server
      # used in this benchmark will fail to start.
      # Using an actual Datadog agent instead of the fake server should not
      # affect the indication of whether the rate limit is reachable
      # since the agent shouldn't take longer to process than the fake
      # web server (and the agent should also run on another core),
      # however using a real agent would forego reports of the number of
      # snapshots submitted and their size.
      server.start
    end

    require_relative 'support/di_snapshot_target'
  end

  def run_benchmark
    probe = Datadog::DI::Probe.new(
      id: 1, type: :log,
      type_name: 'DISnapshotTarget', method_name: 'test_method',
      rate_limit: BASIC_RATE_LIMIT,
    )

    unless probe_manager.add_probe(probe)
      raise "Failed to instrument method (without snapshot capture)"
    end

    @received_snapshot_count = 0
    @received_snapshot_bytes = 0

    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? { time: 0.01, warmup: 0 } : { time: 10, warmup: 2 }
      x.config(
        **benchmark_time,
      )

      x.report('method probe - basic') do
        BASIC_RATE_LIMIT.times do
          DISnapshotTarget.new.test_method
        end
        Datadog::DI.component.probe_notifier_worker.flush
      end

      x.save! 'di-snapshot-results.json' unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end

    # DI does not provide an API to remove a specific probe because
    # this functionality is currently not needed by the product.
    probe_manager.remove_other_probes([])

    puts "Received #{@received_snapshot_count} snapshots, #{@received_snapshot_bytes} bytes total"

    probe = Datadog::DI::Probe.new(
      id: 1, type: :log,
      type_name: 'DISnapshotTarget', method_name: 'test_method',
      capture_snapshot: true,
      # Normally rate limit for enriched probes is 1.
      # To get a meaningful number of submissions, increase it to 20.
      # We should get about 200 snapshots in the 10 seconds that the
      # benchmark is supposed to run.
      rate_limit: ENRICHED_RATE_LIMIT,
    )

    unless probe_manager.add_probe(probe)
      raise "Failed to instrument method (with snapshot capture)"
    end

    @received_snapshot_count = 0
    @received_snapshot_bytes = 0

    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? { time: 0.01, warmup: 0 } : { time: 10, warmup: 2 }
      x.config(
        **benchmark_time,
      )

      x.report('method probe - enriched') do
        ENRICHED_RATE_LIMIT.times do
          DISnapshotTarget.new.test_method
        end
        Datadog::DI.component.probe_notifier_worker.flush
      end

      x.save! 'di-snapshot-results.json' unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end

    probe_manager.remove_other_probes([])

    puts "Received #{@received_snapshot_count} snapshots, #{@received_snapshot_bytes} bytes total"

    probe = Datadog::DI::Probe.new(
      id: 1, type: :log,
      file: 'di_snapshot_target.rb', line_no: 20,
      capture_snapshot: false,
      rate_limit: BASIC_RATE_LIMIT,
    )

    unless probe_manager.add_probe(probe)
      raise "Failed to instrument line (with snapshot capture)"
    end

    @received_snapshot_count = 0
    @received_snapshot_bytes = 0

    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? { time: 0.01, warmup: 0 } : { time: 10, warmup: 2 }
      x.config(
        **benchmark_time,
      )

      x.report('line probe - basic') do
        BASIC_RATE_LIMIT.times do
          DISnapshotTarget.new.test_method
        end
        Datadog::DI.component.probe_notifier_worker.flush
      end

      x.save! 'di-snapshot-results.json' unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end

    probe_manager.remove_other_probes([])

    puts "Received #{@received_snapshot_count} snapshots, #{@received_snapshot_bytes} bytes total"

    probe = Datadog::DI::Probe.new(
      id: 1, type: :log,
      file: 'di_snapshot_target.rb', line_no: 20,
      capture_snapshot: true,
      rate_limit: ENRICHED_RATE_LIMIT,
    )

    unless probe_manager.add_probe(probe)
      raise "Failed to instrument line (with snapshot capture)"
    end

    @received_snapshot_count = 0
    @received_snapshot_bytes = 0

    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? { time: 0.01, warmup: 0 } : { time: 10, warmup: 2 }
      x.config(
        **benchmark_time,
      )

      x.report('line probe - enriched') do
        ENRICHED_RATE_LIMIT.times do
          DISnapshotTarget.new.test_method
        end
        Datadog::DI.component.probe_notifier_worker.flush
      end

      x.save! 'di-snapshot-results.json' unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end

    probe_manager.remove_other_probes([])

    puts "Received #{@received_snapshot_count} snapshots, #{@received_snapshot_bytes} bytes total"
  end

  private

  def probe_manager
    Datadog::DI.component.probe_manager
  end

  def server
    WEBrick::HTTPServer.new(
      Port: 8126,
    ).tap do |server|
      @received_snapshot_count = 0
      @received_snapshot_bytes = 0

      server.mount_proc('/debugger/v1/diagnostics') do |req, res|
        # This request is a multipart form post
      end

      server.mount_proc('/debugger/v1/input') do |req, res|
        payload = JSON.parse(req.body)
        @received_snapshot_count += payload.length
        @received_snapshot_bytes += req.body.length
      end
    end
  end

  attr_reader :received_snapshot_count
end

puts "Current pid is #{Process.pid}"

DISnapshotBenchmark.new.instance_exec do
  run_benchmark
end
