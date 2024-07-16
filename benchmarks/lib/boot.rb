# Used to quickly run benchmark under RSpec as part of the usual test suite, to validate it didn't bitrot
VALIDATE_BENCHMARK_MODE = ENV['VALIDATE_BENCHMARK'] == 'true'

class Benchmarker
  def initialize(source_file)
    @source_file = source_file
    @before_blocks = []
    @after_blocks = []
    @benchmarks = []
    @default_benchmark_time = 10
  end

  attr_reader :source_file
  attr_reader :before_blocks
  attr_reader :after_blocks
  attr_reader :benchmarks

  def default_benchmark_time(*args)
    if args.any?
      if args.length > 1
        raise ArgumentError, 'Zero or one arguments are required'
      end
      @default_benchmark_time = args.first
    else
      @default_benchmark_time
    end
  end

  def source_file_without_ext
    source_file.sub(/\.rb\z/, '')
  end

  def before(&block)
    before_blocks << block
  end

  def after(&block)
    after_blocks << block
  end

  def benchmark(name, time: nil, &block)
    benchmarks << lambda do
      Benchmark.ips do |x|
        _benchmark_time = VALIDATE_BENCHMARK_MODE ? { time: 0.01, warmup: 0 } : { time: time || default_benchmark_time, warmup: 2 }
        x.config(
          **_benchmark_time,
          suite: report_to_dogstatsd_if_enabled_via_environment_variable(benchmark_name: source_file_without_ext)
        )

        x.report(name, &block)

        x.save! "#{source_file_without_ext}-results.json" unless VALIDATE_BENCHMARK_MODE
        x.compare!
      end
    end
  end

  def report_pid
    puts "Current pid is #{Process.pid}"
  end

  def run
    forever = ARGV.include?('--forever')
    if forever && !respond_to?(:run_forever)
      raise "Benchmark does not define run_forever method"
    end

    report_pid

    before_blocks.map(&:call)

    if forever
      run_forever
    else
      run_benchmarks
      run_after
    end
  end

  def run_benchmarks
    benchmarks.map(&:call)
  end

  def run_after
    after_blocks.map(&:call)
  end
end

def benchmarks(source_file, &block)
  return unless source_file == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

  require 'benchmark/ips'
  require 'datadog'
  require 'pry'
  require_relative 'dogstatsd_reporter'

  # Create a new class so that methods can delegate to the base
  # implementation via super.
  Class.new(Benchmarker).new(source_file).tap do |benchmarker|
    benchmarker.instance_exec(&block)
  end.run
end
