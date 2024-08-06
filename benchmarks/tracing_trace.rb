require_relative 'support/boot'

Benchmarker.define do
  module NoopWriter
    def write(trace)
      # no-op
    end
  end

  # @param [Integer] time in seconds. The default is 12 seconds because having over 105 samples allows the
  #   benchmarking platform to calculate helpful aggregate stats. Because benchmark-ips tries to run one iteration
  #   per 100ms, this means we'll have around 120 samples (give or take a small margin of error).
  # @param [Integer] warmup in seconds. The default is 2 seconds.
  default_benchmark_time 12

  before do
    ::Datadog::Tracing::Writer.prepend(NoopWriter)
  end

  [1, 10, 100].each do |depth_|
    depth = depth_

    benchmark "#{depth} span trace - no writer" do
      (depth.times.map { "Datadog::Tracing.trace('op.name') {" } + depth.times.map { "}" }).join
    end
  end
end

Benchmarker.define do
  module NoopAdapter
    Response = Struct.new(:code, :body)

    def open
      Response.new(200)
    end
  end

  default_benchmark_time 12

  before do
    ::Datadog::Core::Transport::HTTP::Adapters::Net.prepend(NoopAdapter)
  end

  # Because the writer runs in the background, on a timed interval, benchmark results will have
  # dips (lower ops/sec) whenever the writer wakes up and consumes all pending traces.
  # This is OK for our measurements, because we want to measure the full performance cost,
  # but it creates high variability, depending on the sampled interval.
  # This means that this benchmark will be marked as internally "unstable",
  # but we trust it's total average result.
  [1, 10, 100].each do |depth_|
    depth = depth_

    benchmark "#{depth} span trace - no network" do
      (depth.times.map { "Datadog::Tracing.trace('op.name') {" } + depth.times.map { "}" }).join
    end
  end
end

Benchmarker.define do
  default_benchmark_time 12

  around do |block|
    Datadog::Tracing.trace('op.name') do |span, trace|
      @trace = trace
      unless block
        require'byebug';byebug
      end
      block.call
    end
  end

  benchmark "trace.to_digest" do
    @trace.to_digest
  end

  benchmark "trace.to_digest - Continue" do
    digest = @trace.to_digest
    Datadog::Tracing.continue_trace!(digest)
  end
end

Benchmarker.define do
  benchmark "Tracing.log_correlation" do
    Datadog::Tracing.log_correlation
  end
end

Benchmarker.define do
  before do
    Datadog.configure do |c|
      if defined?(c.tracing.distributed_tracing.propagation_extract_style)
        # Required to run benchmarks against ddtrace 1.x.
        # Can be removed when 2.0 is merged to master.
        c.tracing.distributed_tracing.propagation_style = ['datadog']
      else
        c.tracing.propagation_style = ['datadog']
      end
    end
  end

  around do |block|
    Datadog::Tracing.trace('op.name') do |span, trace|
      @injected_trace_digest = trace.to_digest
      block.call
    end
  end

  benchmark "Propagation - Datadog" do
    env = {}
    Datadog::Tracing::Contrib::HTTP.inject(@injected_trace_digest, env)
    extracted_trace_digest = Datadog::Tracing::Contrib::HTTP.extract(env)
    raise unless extracted_trace_digest
  end
end

Benchmarker.define do
  #run_in_fork

  before do
    Datadog.configure do |c|
      c.tracing.propagation_style = ['tracecontext']
    end
  end

  around do |block|
    Datadog::Tracing.trace('op.name') do |span, trace|
      @injected_trace_digest = trace.to_digest
      block.call
    end
  end

  benchmark "Propagation - Trace Context" do
    env = {}
    Datadog::Tracing::Contrib::HTTP.inject(@injected_trace_digest, env)
    extracted_trace_digest = Datadog::Tracing::Contrib::HTTP.extract(env)
    raise unless extracted_trace_digest
  end
end

puts "Current pid is #{Process.pid}"

def run_benchmark(&block)
  # Forking to avoid monkey-patching leaking between benchmarks
  pid = fork { block.call }
  _, status = Process.wait2(pid)

  raise "Benchmark failed with status #{status}" unless status.success?
end

TracingTraceBenchmark.new.instance_exec do
  run_benchmark { benchmark_no_writer }
  run_benchmark { benchmark_no_network }
  run_benchmark { benchmark_to_digest }
  run_benchmark { benchmark_log_correlation }
  run_benchmark { benchmark_to_digest_continue }
  run_benchmark { benchmark_propagation_datadog }
  run_benchmark { benchmark_propagation_trace_context }
end
