# Used to quickly run benchmark under RSpec as part of the usual test suite, to validate it didn't bitrot
VALIDATE_BENCHMARK_MODE = ENV['VALIDATE_BENCHMARK'] == 'true'

return unless __FILE__ == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

require_relative 'benchmarks_helper'
require 'open3'

class GemLoadingBenchmark
  def benchmark_gem_loading
    # This benchmark needs to be run in a clean environment where datadog is
    # not loaded yet.
    #
    # Now that this benchmark is in its own file, it does not need
    # to spawn a subprocess IF we would always execute this benchmark
    # file by itself.
    output, status = Open3.capture2e('bundle', 'exec', 'ruby', stdin_data: <<-RUBY)
      raise "Datadog is already loaded" if defined?(::Datadog::Core)

      lib = File.expand_path('../lib', '#{__dir__}')
      $LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
      $LOAD_PATH.unshift('#{__dir__}')

      VALIDATE_BENCHMARK_MODE = #{VALIDATE_BENCHMARK_MODE}
      require 'benchmarks_ips_patch'

      Benchmark.ips do |x|
        # Gem loading is quite slower than the other microbenchmarks
        benchmark_time = VALIDATE_BENCHMARK_MODE ? { time: 0.001, warmup: 0 } : { time: 60, warmup: 5 }
        x.config(**benchmark_time)

        x.report("Gem loading") do
          pid = fork { require 'datadog' }

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

GemLoadingBenchmark.new.instance_exec do
  benchmark_gem_loading
end
