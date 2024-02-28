# Used to quickly run benchmark under RSpec as part of the usual test suite, to validate it didn't bitrot
VALIDATE_BENCHMARK_MODE = ENV['VALIDATE_BENCHMARK'] == 'true'

return unless __FILE__ == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

require 'benchmark/ips'
require 'open3'

require 'ddtrace'

class TracingTraceBenchmark
  module NoopWriter
    def write(trace)
      # no-op
    end
  end

  module NoopAdapter
    Response = Struct.new(:code, :body)

    def open
      Response.new(200)
    end
  end

  def benchmark_time(time: 10.5, warmup: 2)
    VALIDATE_BENCHMARK_MODE ? { time: 0.001, warmup: 0 } : { time: time, warmup: warmup }
  end

  def benchmark_no_writer
    ::Datadog::Tracing::Writer.prepend(NoopWriter)

    Benchmark.ips do |x|
      x.config(**benchmark_time(time: 20))

      def trace(x, depth)
        x.report(
          "#{depth} span trace - no writer",
          (depth.times.map { "Datadog::Tracing.trace('op.name') {" } + depth.times.map { "}" }).join
        )
      end

      trace(x, 1)
      trace(x, 10)
      trace(x, 100)

      x.save! "#{__FILE__}-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end
  end

  def benchmark_no_network
    ::Datadog::Core::Transport::HTTP::Adapters::Net.prepend(NoopAdapter)

    Benchmark.ips do |x|
      x.config(**benchmark_time(time: 20))

      def trace(x, depth)
        x.report(
          "#{depth} span trace - no network",
          (depth.times.map { "Datadog::Tracing.trace('op.name') {" } + depth.times.map { "}" }).join
        )
      end

      trace(x, 1)
      trace(x, 10)
      trace(x, 100)

      x.save! "#{__FILE__}-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end
  end

  def benchmark_to_digest
    Datadog::Tracing.trace('op.name') do |span, trace|
      Benchmark.ips do |x|
        x.config(**benchmark_time)

        x.report("trace.to_digest") do
          trace.to_digest
        end

        x.save! "#{__FILE__}-results.json" unless VALIDATE_BENCHMARK_MODE
        x.compare!
      end
    end
  end

  def benchmark_log_correlation
    Datadog::Tracing.trace('op.name') do |span, trace|
      Benchmark.ips do |x|
        x.config(**benchmark_time)

        x.report("Tracing.log_correlation") do
          Datadog::Tracing.log_correlation
        end

        x.save! "#{__FILE__}-results.json" unless VALIDATE_BENCHMARK_MODE
        x.compare!
      end
    end
  end

  def benchmark_to_digest_continue
    Datadog::Tracing.trace('op.name') do |span, trace|
      Benchmark.ips do |x|
        x.config(**benchmark_time)

        x.report("trace.to_digest - Continue") do
          digest = trace.to_digest
          Datadog::Tracing.continue_trace!(digest)
        end

        x.save! "#{__FILE__}-results.json" unless VALIDATE_BENCHMARK_MODE
        x.compare!
      end
    end
  end

  def benchmark_propagation_datadog
    Datadog.configure do |c|
      if defined?(c.tracing.distributed_tracing.propagation_extract_style)
        # Required to run benchmarks against ddtrace 1.x.
        # Can be removed when 2.0 is merged to master.
        c.tracing.distributed_tracing.propagation_style = ['datadog']
      else
        c.tracing.propagation_style = ['datadog']
      end
    end

    Datadog::Tracing.trace('op.name') do |span, trace|
      injected_trace_digest = trace.to_digest
      Benchmark.ips do |x|
        x.config(**benchmark_time)

        x.report("Propagation - Datadog") do
          env = {}
          Datadog::Tracing::Contrib::HTTP.inject(injected_trace_digest, env)
          extracted_trace_digest = Datadog::Tracing::Contrib::HTTP.extract(env)
          raise unless extracted_trace_digest
        end

        x.save! "#{__FILE__}-results.json" unless VALIDATE_BENCHMARK_MODE
        x.compare!
      end
    end
  end

  def benchmark_propagation_trace_context
    Datadog.configure do |c|
      c.tracing.propagation_style = ['tracecontext']
    end

    Datadog::Tracing.trace('op.name') do |span, trace|
      injected_trace_digest = trace.to_digest
      Benchmark.ips do |x|
        x.config(**benchmark_time)

        x.report("Propagation - Trace Context") do
          env = {}
          Datadog::Tracing::Contrib::HTTP.inject(injected_trace_digest, env)
          extracted_trace_digest = Datadog::Tracing::Contrib::HTTP.extract(env)
          raise unless extracted_trace_digest
        end

        x.save! "#{__FILE__}-results.json" unless VALIDATE_BENCHMARK_MODE
        x.compare!
      end
    end
  end

  def benchmark_gem_loading
    # This benchmark needs to be run in a clean environment where ddtrace is not loaded yet
    output, status = Open3.capture2e('ruby', stdin_data: <<-RUBY)
      raise "Datadog is already loaded" if defined?(::Datadog)

      VALIDATE_BENCHMARK_MODE = ENV['VALIDATE_BENCHMARK'] == 'true'
      require 'benchmark/ips'
      
      Benchmark.ips do |x|
        # Gem loading is quite slower than the other microbenchmarks
        benchmark_time = VALIDATE_BENCHMARK_MODE ? { time: 0.001, warmup: 0 } : { time: 60, warmup: 5 }
        x.config(**benchmark_time)
  
        x.report("Gem loading") do
          pid = fork { require 'ddtrace' }
  
          _, status = Process.wait2(pid)
          raise unless status.success?
        end
  
        x.save! "#{__FILE__}-results.json" unless VALIDATE_BENCHMARK_MODE
        x.compare!
      end
    RUBY

    print output

    raise "Benchmark failed with status #{status}: #{output}" unless status.success?
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
  run_benchmark { benchmark_gem_loading }
end
