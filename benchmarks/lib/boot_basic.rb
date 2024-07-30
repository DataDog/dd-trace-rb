# Used to quickly run benchmark under RSpec as part of the usual test suite, to validate it didn't bitrot
VALIDATE_BENCHMARK_MODE = ENV['VALIDATE_BENCHMARK'] == 'true'

class BasicBenchmarker
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
          suite: suite_for_dogstatsd_reporting(benchmark_name: source_file_without_ext)
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

  class << self
    def define(&block)
      caller_path = caller_locations.first.path

      return unless caller_path == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

      require 'benchmark/ips'

      preload_libs

      # Create a new class so that methods can delegate to the base
      # implementation via super.
      cls_name = File.basename(caller_path).sub(/\.rb\z/, '').gsub(/_(\w)/) { |m| m[1..].upcase }.gsub(/\A(.)/) { |m| m.upcase }
      cls = Class.new(self).new(caller_path)
      Object.const_set(cls_name, cls)
      cls.instance_exec(&block)
      cls.run
    end

    def preload_libs
      # Do not preload anything in the basic benchmarker.
      # Regular benchmarker preloads datadog and pry for convenience.
    end
  end

  def suite_for_dogstatsd_reporting(**args)
    # Basic benchmarker cannot have datadog loaded, therefore
    # it is currently unable to report stats to dogstatsd.
    if ENV['REPORT_TO_DOGSTATSD'] == 'true'
      warn "reporting to dogstatsd has been requested but the basic benchmarker is not able to report to dogstatsd"
    end
    nil
  end
end
